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
  gh label create autobot-in-review --repo "$repo" --color B60205 --description "Task is assigned to an implementation run" --force >/dev/null
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

  set +e
  if codex exec --help >/dev/null 2>&1; then
    codex exec "$(cat "$prompt_file")" >"$log_file" 2>&1
  elif codex --help 2>/dev/null | grep -q -- "--prompt"; then
    codex --prompt "$(cat "$prompt_file")" >"$log_file" 2>&1
  else
    {
      echo "RESULT: blocked"
      echo "SUMMARY: Codex CLI did not expose a supported non-interactive mode."
    } >"$log_file"
    set -e
    return 0
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

require_copilot_assignee_or_block() {
  local repo="$1"
  local issue_number="$2"
  local trigger_label="$3"
  local run_url="$4"
  if [[ -z "${AUTOBOT_COPILOT_ASSIGNEE:-}" ]]; then
    blocked_and_exit "$repo" "$issue_number" "$trigger_label" "AUTOBOT_COPILOT_ASSIGNEE is required when provider is github-copilot." "$run_url"
  fi
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
