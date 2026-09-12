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
  gh label create autobot-implementing --repo "$repo" --color 0E8A16 --description "Design approved and ready for task planning" --force >/dev/null
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
