#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmd() {
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "missing required command: $cmd" >&2
      exit 1
    fi
  done
}

slugify() {
  python - "$1" <<'PY'
import re
import sys
value = sys.argv[1]
slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
if not slug:
    slug = "item"
print(slug[:60])
PY
}

result_from_log() {
  python - "$1" <<'PY'
import pathlib
import re
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
match = re.search(r"^RESULT:\s*(completed|blocked)\s*$", text, re.IGNORECASE | re.MULTILINE)
print(match.group(1).lower() if match else "blocked")
PY
}

summary_from_log() {
  python - "$1" <<'PY'
import pathlib
import re
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
match = re.search(r"^SUMMARY:\s*(.+)$", text, re.IGNORECASE | re.MULTILINE)
print(match.group(1).strip() if match else "")
PY
}

provider_for_phase() {
  local phase="$1"
  local value=""
  case "$phase" in
    spec) value="${AUTOBOT_SPEC_PROVIDER:-codex}" ;;
    plan) value="${AUTOBOT_PLAN_PROVIDER:-codex}" ;;
    implement) value="${AUTOBOT_IMPLEMENT_PROVIDER:-codex}" ;;
    *)
      echo "invalid phase for provider routing: $phase" >&2
      return 1
      ;;
  esac
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    codex|github-copilot) printf '%s' "$value" ;;
    *)
      echo "invalid provider value for phase '$phase': $value (allowed: codex, github-copilot)" >&2
      return 2
      ;;
  esac
}

ensure_provider_valid_or_block() {
  local phase="$1"
  local repo="$2"
  local issue_number="$3"
  local trigger_label="$4"
  local run_url="$5"
  if ! provider_for_phase "$phase" >/dev/null; then
    blocked_and_exit "$repo" "$issue_number" "$trigger_label" "$(provider_for_phase "$phase" 2>&1 || true)" "$run_url"
  fi
}

actor_has_write_access() {
  local repo="$1"
  local actor="$2"
  local permission
  if ! permission="$(gh api "repos/${repo}/collaborators/${actor}/permission" --jq .permission 2>/dev/null)"; then
    echo "false"
    return 0
  fi
  case "$permission" in
    admin|maintain|write) echo "true" ;;
    *) echo "false" ;;
  esac
}

issue_title_from_json() {
  python - "$1" <<'PY'
import json
import pathlib
import sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("title", ""))
PY
}

issue_labels_from_json() {
  python - "$1" <<'PY'
import json
import pathlib
import sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
labels = [label.get("name", "") for label in data.get("labels", []) if isinstance(label, dict)]
print("\n".join(labels))
PY
}

ensure_autobot_labels() {
  local repo="$1"
  gh label create autobot-ready-for-spec --repo "$repo" --color 1D76DB --description "Feature is ready for design generation" --force >/dev/null
  gh label create autobot-creating-specification --repo "$repo" --color 5319E7 --description "Design exists and awaits human review" --force >/dev/null
  gh label create autobot-review-specification --repo "$repo" --color C5DEF5 --description "Final design review before implementation planning" --force >/dev/null
  gh label create autobot-ready-to-implement --repo "$repo" --color 0E8A16 --description "Specification approved and ready for task planning" --force >/dev/null
  gh label create autobot-task --repo "$repo" --color FBCA04 --description "Task issue generated for implementation" --force >/dev/null
  gh label create autoboot --repo "$repo" --color FBCA04 --description "Compatibility task marker label for autobot-generated implementation tasks" --force >/dev/null
  gh label create autobot-implementing --repo "$repo" --color D4C5F9 --description "Task implementation is in progress" --force >/dev/null
  gh label create autobot-in-review --repo "$repo" --color B60205 --description "Implementation is complete and awaits human PR review" --force >/dev/null
  gh label create autobot-blocked --repo "$repo" --color D93F0B --description "Needs human decision before continuing" --force >/dev/null
}

project_sync_is_configured() {
  [[ -n "${PROJECT_OWNER:-}" && -n "${PROJECT_NUMBER:-}" ]]
}

sync_project_stage_for_issue() {
  local repo="$1"
  local issue_number="$2"
  local stage="$3"

  if ! project_sync_is_configured; then
    return 0
  fi

  local issue_url="https://github.com/${repo}/issues/${issue_number}"
  local status_field="${PROJECT_STATUS_FIELD:-Status}"
  local token="${AUTOBOT_PROJECT_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
  local previous_gh_token="${GH_TOKEN:-}"

  if [[ -n "$token" ]]; then
    export GH_TOKEN="$token"
  fi

  local add_output
  if ! add_output="$(gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$issue_url" --format json 2>&1)"; then
    if ! printf '%s' "$add_output" | grep -Eqi 'already (exists|added)|item .* already'; then
      if [[ -n "$previous_gh_token" ]]; then
        export GH_TOKEN="$previous_gh_token"
      fi
      echo "project sync add failed: $add_output" >&2
      return 1
    fi
  fi

  local edit_output
  if ! edit_output="$(gh project item-edit "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$issue_url" --field "$status_field" --value "$stage" --format json 2>&1)"; then
    if [[ -n "$previous_gh_token" ]]; then
      export GH_TOKEN="$previous_gh_token"
    fi
    echo "project sync edit failed: $edit_output" >&2
    return 1
  fi

  if [[ -n "$previous_gh_token" ]]; then
    export GH_TOKEN="$previous_gh_token"
  fi
  return 0
}

sync_project_stage_with_warning() {
  local repo="$1"
  local issue_number="$2"
  local stage="$3"

  if ! sync_project_stage_for_issue "$repo" "$issue_number" "$stage"; then
    local warning
    warning=$(
      cat <<EOF
Autobot warning: failed to sync Project stage to \`${stage}\`.

Configure Project sync with:
- PROJECT_OWNER
- PROJECT_NUMBER
- optional PROJECT_STATUS_FIELD (defaults to Status)
- AUTOBOT_PROJECT_TOKEN with project write access
EOF
    )
    gh issue comment "$issue_number" --repo "$repo" --body "$warning" >/dev/null || true
    return 1
  fi
  return 0
}

guard_text_file() {
  python "$SCRIPT_DIR/guard_text.py" --file "$1"
}

guard_text_literal() {
  python "$SCRIPT_DIR/guard_text.py"
}

blocked_and_exit() {
  local repo="$1"
  local issue_number="$2"
  local trigger_label="$3"
  local reason="$4"
  local run_url="$5"

  local message
  message=$(
    cat <<EOF
Autobot run is blocked.

Reason: ${reason}

Run: ${run_url}
EOF
  )

  if ! printf '%s' "$message" | guard_text_literal >/dev/null 2>&1; then
    message="Autobot run is blocked and the generated message was redacted by secret guard. Run: ${run_url}"
  fi

  gh issue comment "$issue_number" --repo "$repo" --body "$message" >/dev/null || true
  gh issue edit "$issue_number" --repo "$repo" --remove-label "$trigger_label" --add-label autobot-blocked >/dev/null || true
  sync_project_stage_with_warning "$repo" "$issue_number" "Blocked" || true
  exit 0
}

run_codex_prompt() {
  local prompt_file="$1"
  local log_file="$2"
  local prompt
  local help_text=""
  local status=0
  prompt="$(cat "$prompt_file")"

  set +e
  if codex exec --help >/dev/null 2>&1; then
    help_text="$(codex exec --help 2>&1 || true)"

    local -a exec_cmd
    exec_cmd=(codex exec)
    if grep -q -- '--approve-for-me' <<<"$help_text"; then
      exec_cmd+=(--approve-for-me)
    elif grep -q -- '--sandbox' <<<"$help_text"; then
      exec_cmd+=(--sandbox workspace-write)
    fi

    "${exec_cmd[@]}" - < "$prompt_file" >"$log_file" 2>&1
    status=$?

    if [[ "${GITHUB_ACTIONS:-}" == "true" ]] && grep -q -- '--dangerously-bypass-approvals-and-sandbox' <<<"$help_text" && grep -Eqi 'bwrap:|Failed RTM_NEWADDR|execution sandbox failed|read-only filesystem permissions|Operation not permitted' "$log_file"; then
      codex exec --dangerously-bypass-approvals-and-sandbox - < "$prompt_file" >"$log_file" 2>&1
      status=$?
    fi

    if [[ $status -ne 0 ]] && grep -Eqi "For more information, try '--help'|unrecognized option|unknown option|unexpected argument" "$log_file"; then
      if codex --help 2>/dev/null | grep -q -- "--prompt"; then
        codex --prompt "$prompt" >"$log_file" 2>&1
        status=$?
      fi
    fi
  elif codex --help 2>/dev/null | grep -q -- "--prompt"; then
    codex --prompt "$prompt" >"$log_file" 2>&1
    status=$?
  else
    {
      echo "RESULT: blocked"
      echo "SUMMARY: Codex CLI did not expose a supported non-interactive mode."
    } >"$log_file"
    set -e
    return 0
  fi

  if ! grep -Eiq '^RESULT:\s*(completed|blocked)\s*$' "$log_file"; then
    local diagnostic_line
    diagnostic_line="$(grep -Eim1 'error:|unrecognized option|unknown option|unexpected argument|invalid value|Operation not permitted|bwrap:' "$log_file" || true)"
    if [[ -z "$diagnostic_line" ]]; then
      diagnostic_line="$(grep -v '^[[:space:]]*$' "$log_file" | tail -n 1 || true)"
    fi
    if [[ -z "$diagnostic_line" ]]; then
      diagnostic_line="No diagnostic output from Codex CLI."
    fi
    {
      cat "$log_file"
      echo
      echo "RESULT: blocked"
      echo "SUMMARY: Codex CLI did not return RESULT/SUMMARY contract. Diagnostic: ${diagnostic_line}"
    } > "${log_file}.tmp"
    mv "${log_file}.tmp" "$log_file"
  fi
  set -e
}

copilot_timeout_minutes() {
  local raw="${AUTOBOT_COPILOT_TIMEOUT_MINUTES:-90}"
  if ! [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo 90
    return 0
  fi
  if (( raw < 1 )); then
    echo 90
    return 0
  fi
  if (( raw > 360 )); then
    echo 360
    return 0
  fi
  echo "$raw"
}

flag_is_true() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_sas_token() {
  local token="$1"
  token="${token#\?}"
  printf '%s' "$token"
}

urlencode_blob_path() {
  python - "$1" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe='/-_.~'))
PY
}

render_markdown_to_html_file() {
  local markdown_path="$1"
  local html_path="$2"
  if command -v pandoc >/dev/null 2>&1; then
    pandoc "$markdown_path" --from gfm --to html5 --standalone --output "$html_path" >/dev/null 2>&1
    return 0
  fi
  python - "$markdown_path" "$html_path" <<'PY'
import html
import pathlib
import re
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
title = "Autobot design artifact"
for line in source.splitlines():
    match = re.match(r"^#\s+(.+)$", line)
    if match:
        title = match.group(1).strip()
        break
body = html.escape(source)
document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; margin: 2rem; line-height: 1.5; }}
    pre {{ white-space: pre-wrap; word-break: break-word; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  <pre>{body}</pre>
</body>
</html>
"""
pathlib.Path(sys.argv[2]).write_text(document, encoding="utf-8")
PY
}

upload_blob_file_with_sas() {
  local local_path="$1"
  local account="$2"
  local endpoint_suffix="$3"
  local container="$4"
  local blob_path="$5"
  local sas_token="$6"
  local content_type="$7"

  local encoded_blob
  encoded_blob="$(urlencode_blob_path "$blob_path")"
  local url="https://${account}.${endpoint_suffix}/${container}/${encoded_blob}?${sas_token}"

  curl --silent --show-error --fail \
    --request PUT \
    --header "x-ms-version: 2023-11-03" \
    --header "x-ms-blob-type: BlockBlob" \
    --header "Content-Type: ${content_type}" \
    --data-binary "@${local_path}" \
    "$url" >/dev/null 2>&1
}

publish_spec_artifacts() {
  local repo="$1"
  local issue_number="$2"
  local branch_name="$3"
  local design_markdown_path="$4"

  SPEC_ARTIFACTS_ENABLED="false"
  SPEC_ARTIFACTS_WARNING=""
  SPEC_ARTIFACTS_MD_URL=""
  SPEC_ARTIFACTS_HTML_URL=""
  SPEC_ARTIFACTS_LATEST_URL=""
  SPEC_ARTIFACTS_LINKS_MARKDOWN=""

  if ! flag_is_true "${AUTOBOT_SPEC_ARTIFACTS_ENABLED:-false}"; then
    return 0
  fi
  SPEC_ARTIFACTS_ENABLED="true"

  local account="${AUTOBOT_SPEC_ARTIFACTS_STORAGE_ACCOUNT:-}"
  local container="${AUTOBOT_SPEC_ARTIFACTS_CONTAINER:-}"
  local prefix_root="${AUTOBOT_SPEC_ARTIFACTS_PREFIX:-autobot-spec}"
  local endpoint_suffix="${AUTOBOT_SPEC_ARTIFACTS_ENDPOINT_SUFFIX:-blob.core.windows.net}"
  local write_sas read_sas
  write_sas="$(normalize_sas_token "${AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS:-}")"
  read_sas="$(normalize_sas_token "${AUTOBOT_SPEC_ARTIFACTS_READ_SAS:-}")"
  if [[ -z "$account" || -z "$container" || -z "$write_sas" || -z "$read_sas" ]]; then
    SPEC_ARTIFACTS_WARNING="Spec artifact publishing is enabled, but Azure Blob settings or SAS secrets are missing."
    return 0
  fi
  if [[ ! -f "$design_markdown_path" ]]; then
    SPEC_ARTIFACTS_WARNING="Spec artifact publishing is enabled, but the design markdown file was not found for upload."
    return 0
  fi

  local owner name
  owner="${repo%%/*}"
  name="${repo#*/}"
  local run_id
  run_id="${GITHUB_RUN_ID:-manual-$(date +%s)}"
  local base_prefix="${prefix_root}/${owner}/${name}/${branch_name}/issue-${issue_number}"
  local run_prefix="${base_prefix}/runs/${run_id}"
  local blob_md="${run_prefix}/design.md"
  local blob_html="${run_prefix}/design.html"
  local blob_latest="${base_prefix}/latest.json"

  local html_tmp=".autobot/output/spec-artifact-design.html"
  if ! render_markdown_to_html_file "$design_markdown_path" "$html_tmp"; then
    SPEC_ARTIFACTS_WARNING="Spec artifact publishing is enabled, but generating design.html from design.md failed."
    return 0
  fi

  if ! upload_blob_file_with_sas "$design_markdown_path" "$account" "$endpoint_suffix" "$container" "$blob_md" "$write_sas" "text/markdown; charset=utf-8"; then
    SPEC_ARTIFACTS_WARNING="Spec artifact publishing failed while uploading design.md to Azure Blob Storage."
    return 0
  fi
  if ! upload_blob_file_with_sas "$html_tmp" "$account" "$endpoint_suffix" "$container" "$blob_html" "$write_sas" "text/html; charset=utf-8"; then
    SPEC_ARTIFACTS_WARNING="Spec artifact publishing failed while uploading design.html to Azure Blob Storage."
    return 0
  fi

  local source_commit
  source_commit="$(git rev-parse HEAD 2>/dev/null || true)"
  python - "$blob_md" "$blob_html" "$run_id" "$repo" "$branch_name" "$issue_number" "$source_commit" > .autobot/output/spec-latest.json <<'PY'
import json
import sys
payload = {
    "run_id": sys.argv[3],
    "repository": sys.argv[4],
    "branch": sys.argv[5],
    "issue_number": int(sys.argv[6]),
    "source_commit": sys.argv[7],
    "artifacts": {
        "design_md": sys.argv[1],
        "design_html": sys.argv[2],
    },
}
print(json.dumps(payload, indent=2))
PY

  if ! upload_blob_file_with_sas ".autobot/output/spec-latest.json" "$account" "$endpoint_suffix" "$container" "$blob_latest" "$write_sas" "application/json; charset=utf-8"; then
    SPEC_ARTIFACTS_WARNING="Spec artifact publishing failed while updating latest.json in Azure Blob Storage."
    return 0
  fi

  SPEC_ARTIFACTS_MD_URL="https://${account}.${endpoint_suffix}/${container}/$(urlencode_blob_path "$blob_md")?${read_sas}"
  SPEC_ARTIFACTS_HTML_URL="https://${account}.${endpoint_suffix}/${container}/$(urlencode_blob_path "$blob_html")?${read_sas}"
  SPEC_ARTIFACTS_LATEST_URL="https://${account}.${endpoint_suffix}/${container}/$(urlencode_blob_path "$blob_latest")?${read_sas}"
  SPEC_ARTIFACTS_LINKS_MARKDOWN=$(
    cat <<EOF
External spec artifacts:
- Markdown: ${SPEC_ARTIFACTS_MD_URL}
- HTML: ${SPEC_ARTIFACTS_HTML_URL}
- Latest pointer: ${SPEC_ARTIFACTS_LATEST_URL}
EOF
  )
}

copilot_strict_artifact_mode() {
  local raw
  raw="$(printf '%s' "${AUTOBOT_COPILOT_STRICT_ARTIFACT:-false}" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|true|yes|on) echo "true" ;;
    *) echo "false" ;;
  esac
}

copilot_run_token() {
  local phase="$1"
  local issue_number="$2"
  printf 'autobot-%s-%s-%s' "$phase" "$issue_number" "${GITHUB_RUN_ID:-manual}"
}

require_copilot_assignee_or_block() {
  local repo="$1"
  local issue_number="$2"
  local trigger_label="$3"
  local run_url="$4"
  if [[ -z "${AUTOBOT_COPILOT_ASSIGNEE:-}" ]]; then
    blocked_and_exit "$repo" "$issue_number" "$trigger_label" "AUTOBOT_COPILOT_ASSIGNEE is required when provider is github-copilot." "$run_url"
  fi
}

create_or_update_handoff_pr() {
  local phase="$1"
  local repo="$2"
  local issue_number="$3"
  local branch_name="$4"
  local run_token="$5"
  local artifact_path="$6"
  local strict_mode="$7"
  local expected_design_path="${8:-}"

  local pr_title="Autobot ${phase} handoff for issue #${issue_number}"
  mkdir -p .autobot/output
  cat > .autobot/output/handoff-pr-body.md <<EOF
This pull request is the Autobot ${phase} handoff for #${issue_number}.

Run token: \`${run_token}\`
Expected assignee: @${AUTOBOT_COPILOT_ASSIGNEE}
Phase artifact: \`${artifact_path}\`
Strict artifact mode: \`${strict_mode}\`

Completion contract:
1. Keep this PR referencing #${issue_number}.
2. Keep the run token in PR body or PR comments.
3. Update \`${artifact_path}\` with final phase output. In strict mode it must set \`status\` to \`completed\`.
EOF
  if [[ "$phase" == "spec" && -n "$expected_design_path" ]]; then
    cat >> .autobot/output/handoff-pr-body.md <<EOF
4. Keep \`${expected_design_path}\` in this branch and replace its placeholder with the final design before completion.
EOF
  fi

  local pr_number
  pr_number="$(gh pr list --repo "$repo" --head "$branch_name" --json number --jq '.[0].number' 2>/dev/null || true)"
  local pr_url
  if [[ -z "$pr_number" ]]; then
    pr_url="$(gh pr create --repo "$repo" --base "${DEFAULT_BRANCH}" --head "$branch_name" --title "$pr_title" --body-file .autobot/output/handoff-pr-body.md --draft)"
    pr_number="$(gh pr view "$pr_url" --repo "$repo" --json number --jq .number 2>/dev/null || true)"
  else
    gh pr edit "$pr_number" --repo "$repo" --title "$pr_title" --body-file .autobot/output/handoff-pr-body.md >/dev/null
    pr_url="$(gh pr view "$pr_number" --repo "$repo" --json url --jq .url)"
  fi
  printf '%s|%s' "$pr_number" "$pr_url"
}

start_copilot_handoff() {
  local phase="$1"
  local repo="$2"
  local issue_number="$3"
  local branch_name="$4"
  local artifact_path="$5"
  local run_url="$6"
  local trigger_label="$7"
  local expected_design_path="${8:-}"

  require_copilot_assignee_or_block "$repo" "$issue_number" "$trigger_label" "$run_url"

  local run_token timeout_minutes strict_mode
  run_token="$(copilot_run_token "$phase" "$issue_number")"
  timeout_minutes="$(copilot_timeout_minutes)"
  strict_mode="$(copilot_strict_artifact_mode)"

  if ! gh issue edit "$issue_number" --repo "$repo" --add-assignee "$AUTOBOT_COPILOT_ASSIGNEE" >/dev/null 2>&1; then
    blocked_and_exit "$repo" "$issue_number" "$trigger_label" "Failed to assign issue to @${AUTOBOT_COPILOT_ASSIGNEE} for Copilot provider." "$run_url"
  fi

  local pr_data pr_number pr_url
  pr_data="$(create_or_update_handoff_pr "$phase" "$repo" "$issue_number" "$branch_name" "$run_token" "$artifact_path" "$strict_mode" "$expected_design_path")"
  pr_number="${pr_data%%|*}"
  pr_url="${pr_data#*|}"
  if [[ -z "$pr_url" ]]; then
    blocked_and_exit "$repo" "$issue_number" "$trigger_label" "Failed to create or update Copilot handoff PR for branch ${branch_name}." "$run_url"
  fi

  mkdir -p .autobot/copilot
  python - "$phase" "$issue_number" "$branch_name" "$run_token" "$pr_number" "$pr_url" "$artifact_path" <<'PY'
import json
import pathlib
import sys
payload = {
    "phase": sys.argv[1],
    "issue_number": int(sys.argv[2]),
    "branch": sys.argv[3],
    "run_token": sys.argv[4],
    "pr_number": int(sys.argv[5]) if sys.argv[5] else None,
    "pr_url": sys.argv[6],
    "artifact_path": sys.argv[7],
}
path = pathlib.Path(".autobot/copilot/handoff.json")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
PY

  local kickoff
  local design_line=""
  if [[ "$phase" == "spec" && -n "$expected_design_path" ]]; then
    design_line=$'\nExpected design file: `'"${expected_design_path}"$'`'
  fi
  kickoff=$(
    cat <<EOF
Autobot ${phase} provider is set to GitHub Copilot.

Run token: \`${run_token}\`
Expected assignee: @${AUTOBOT_COPILOT_ASSIGNEE}
Handoff PR: ${pr_url}
Branch: \`${branch_name}\`
Phase artifact: \`${artifact_path}\`
${design_line}
Timeout hint: ${timeout_minutes} minutes

Autobot will evaluate completion on pull request updates.
EOF
  )
  gh issue comment "$issue_number" --repo "$repo" --body "$kickoff" >/dev/null || true
  printf '%s' "$pr_url"
}

write_provider_blocked_output() {
  local phase="$1"
  local output_json="$2"
  local reason="$3"
  python - "$phase" "$output_json" "$reason" <<'PY'
import json
import pathlib
import sys
phase = sys.argv[1]
path = pathlib.Path(sys.argv[2])
reason = sys.argv[3]
payload = {"status": "blocked", "blocked_reason": reason}
if phase == "spec":
    payload.update({"issue_comment": "", "pr_title": "", "pr_body": ""})
elif phase == "plan":
    payload.update({"feature_comment": "", "tasks": []})
elif phase == "implement":
    payload.update({"issue_comment": "", "pr_title": "", "pr_body": ""})
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload), encoding="utf-8")
PY
}

pr_contains_token() {
  local repo="$1"
  local pr_number="$2"
  local token="$3"
  local body
  body="$(gh pr view "$pr_number" --repo "$repo" --json body --jq .body 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q "$token"; then
    return 0
  fi
  local comments
  comments="$(gh pr view "$pr_number" --repo "$repo" --comments 2>/dev/null || true)"
  if printf '%s' "$comments" | grep -q "$token"; then
    return 0
  fi
  return 1
}

pr_references_issue() {
  local repo="$1"
  local pr_number="$2"
  local issue_number="$3"
  local issue_url="https://github.com/${repo}/issues/${issue_number}"
  local body
  body="$(gh pr view "$pr_number" --repo "$repo" --json body --jq .body 2>/dev/null || true)"
  if printf '%s' "$body" | grep -Eq "(#${issue_number}\b|${issue_url})"; then
    return 0
  fi
  local comments
  comments="$(gh pr view "$pr_number" --repo "$repo" --comments 2>/dev/null || true)"
  if printf '%s' "$comments" | grep -Eq "(#${issue_number}\b|${issue_url})"; then
    return 0
  fi
  return 1
}

wait_for_copilot_pr() {
  local repo="$1"
  local issue_number="$2"
  local expected_author="$3"
  local token="$4"
  local timeout_minutes="$5"

  local started epoch_now deadline
  started="$(date +%s)"
  deadline=$(( started + timeout_minutes * 60 ))

  while true; do
    local lines
    lines="$(gh pr list --repo "$repo" --state all --limit 200 --json number,author,url,headRefName --jq '.[] | "\(.number)|\(.author.login)|\(.url)|\(.headRefName)"' 2>/dev/null || true)"
    if [[ -n "$lines" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pr_number pr_author pr_url pr_head
        pr_number="${line%%|*}"
        local rest="${line#*|}"
        pr_author="${rest%%|*}"
        rest="${rest#*|}"
        pr_url="${rest%%|*}"
        pr_head="${rest#*|}"
        if [[ "$pr_author" != "$expected_author" ]]; then
          continue
        fi
        if ! pr_references_issue "$repo" "$pr_number" "$issue_number"; then
          continue
        fi
        if pr_contains_token "$repo" "$pr_number" "$token"; then
          printf '%s|%s|%s' "$pr_number" "$pr_url" "$pr_head"
          return 0
        fi
      done <<< "$lines"
    fi
    epoch_now="$(date +%s)"
    if (( epoch_now >= deadline )); then
      return 1
    fi
    sleep 120
  done
}

run_copilot_provider() {
  local phase="$1"
  local repo="$2"
  local issue_number="$3"
  local run_url="$4"
  local output_json="$5"

  require_copilot_assignee_or_block "$repo" "$issue_number" "$TRIGGER_LABEL" "$run_url"

  local run_token="autobot-${phase}-${issue_number}-${GITHUB_RUN_ID:-manual}"
  local timeout_minutes
  timeout_minutes="$(copilot_timeout_minutes)"

  local kickoff
  kickoff=$(
    cat <<EOF
Autobot ${phase} provider is set to GitHub Copilot.

Run token: \`${run_token}\`
Expected assignee: @${AUTOBOT_COPILOT_ASSIGNEE}
Timeout: ${timeout_minutes} minutes

Please produce the required phase artifact and include the run token in the PR description or a PR comment.
EOF
  )
  gh issue comment "$issue_number" --repo "$repo" --body "$kickoff" >/dev/null || true
  if ! gh issue edit "$issue_number" --repo "$repo" --add-assignee "$AUTOBOT_COPILOT_ASSIGNEE" >/dev/null 2>&1; then
    write_provider_blocked_output "$phase" "$output_json" "Failed to assign issue to @${AUTOBOT_COPILOT_ASSIGNEE} for Copilot provider."
    {
      echo "RESULT: blocked"
      echo "SUMMARY: Copilot assignment failed."
    } > "${output_json%.json}.log"
    return 0
  fi

  local pr_data
  if ! pr_data="$(wait_for_copilot_pr "$repo" "$issue_number" "$AUTOBOT_COPILOT_ASSIGNEE" "$run_token" "$timeout_minutes")"; then
    write_provider_blocked_output "$phase" "$output_json" "Timed out waiting for a correlated Copilot PR (token: ${run_token})."
    {
      echo "RESULT: blocked"
      echo "SUMMARY: Timed out waiting for correlated Copilot PR."
    } > "${output_json%.json}.log"
    return 0
  fi

  local pr_number pr_url pr_head
  pr_number="${pr_data%%|*}"
  local rest="${pr_data#*|}"
  pr_url="${rest%%|*}"
  pr_head="${rest#*|}"

  mkdir -p .autobot/output .autobot/copilot
  local artifact_path=".autobot/output/${phase}.json"
  local ref="origin/${pr_head}"
  local artifact_deadline artifact_now artifact_status
  artifact_deadline=$(( $(date +%s) + timeout_minutes * 60 ))

  while true; do
    git fetch origin "$pr_head" >/dev/null 2>&1 || true
    if git show "${ref}:${artifact_path}" > .autobot/copilot/provider.json 2>/dev/null; then
      artifact_status="$(python - <<'PY'
import json
import pathlib
path = pathlib.Path(".autobot/copilot/provider.json")
try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("")
    raise SystemExit(0)
print(str(payload.get("status", "")).strip().lower())
PY
)"
      if [[ "$artifact_status" == "completed" ]]; then
        break
      fi
    fi

    artifact_now="$(date +%s)"
    if (( artifact_now >= artifact_deadline )); then
      write_provider_blocked_output "$phase" "$output_json" "Timed out waiting for correlated Copilot PR artifact ${artifact_path} with status=completed (token: ${run_token})."
      {
        echo "RESULT: blocked"
        echo "SUMMARY: Timed out waiting for correlated Copilot PR artifact."
      } > "${output_json%.json}.log"
      return 0
    fi
    sleep 30
  done

  cp .autobot/copilot/provider.json "$output_json"
  {
    echo "RESULT: completed"
    echo "SUMMARY: Copilot provider output accepted from ${pr_url}."
  } > "${output_json%.json}.log"
  printf '%s' "$pr_url" > .autobot/copilot/pr-url.txt
  return 0
}

run_phase_provider() {
  local phase="$1"
  local prompt_file="$2"
  local log_file="$3"
  local output_json="$4"
  local repo="$5"
  local issue_number="$6"
  local run_url="$7"

  local provider
  if ! provider="$(provider_for_phase "$phase")"; then
    write_provider_blocked_output "$phase" "$output_json" "$(provider_for_phase "$phase" 2>&1 || true)"
    {
      echo "RESULT: blocked"
      echo "SUMMARY: Invalid provider configuration."
    } > "$log_file"
    return 0
  fi

  if [[ "$provider" == "codex" ]]; then
    run_codex_prompt "$prompt_file" "$log_file"
    return 0
  fi

  run_copilot_provider "$phase" "$repo" "$issue_number" "$run_url" "$output_json"
  cp "${output_json%.json}.log" "$log_file"
}
