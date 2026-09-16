#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow_common.sh"

require_cmd gh git python

if [[ -z "${REPOSITORY:-}" || -z "${ISSUE_NUMBER:-}" || -z "${ACTOR:-}" || -z "${DEFAULT_BRANCH:-}" || -z "${TRIGGER_LABEL:-}" ]]; then
  echo "missing required environment values" >&2
  exit 1
fi

ensure_autobot_labels "$REPOSITORY"
ensure_provider_valid_or_block "implement" "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "${WORKFLOW_RUN_URL:-}"

if [[ "$(actor_has_write_access "$REPOSITORY" "$ACTOR")" != "true" ]]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot ignored the label because @$ACTOR does not have write access to this repository." >/dev/null
  gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" >/dev/null || true
  exit 0
fi

provider="$(provider_for_phase implement)"
if [[ "$provider" == "codex" && -z "${CODEX_API_KEY:-}" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Missing CODEX_API_KEY. Grant the org-level secret to this repository before retrying." "${WORKFLOW_RUN_URL:-}"
fi

mkdir -p .autobot/input .autobot/output
gh api "repos/${REPOSITORY}/issues/${ISSUE_NUMBER}" > .autobot/input/issue.json
labels="$(issue_labels_from_json .autobot/input/issue.json)"
if ! printf '%s\n' "$labels" | grep -q '^autobot-task$'; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot refused implementation because this issue is not labelled \`autobot-task\`." >/dev/null
  gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" >/dev/null || true
  exit 0
fi

title="$(issue_title_from_json .autobot/input/issue.json)"
slug="$(slugify "$title")"
branch_name="autobot/${ISSUE_NUMBER}-${slug}"
existing_pr_number="$(gh pr list --repo "$REPOSITORY" --head "$branch_name" --state all --json number --jq '.[0].number' 2>/dev/null || true)"

cat "$SCRIPT_DIR/../prompts/implement.md" > .autobot/input/implement-prompt.md
cat > .autobot/input/rework-context.md <<EOF
Implementation rework context:
- Task issue: #${ISSUE_NUMBER}
- Existing PR number: ${existing_pr_number:-none}
EOF
printf '%s\n' "No CHANGES_REQUESTED reviews were found." > .autobot/input/pr-requested-changes.md
printf '%s\n' "No pull request comments were found." > .autobot/input/pr-comments.txt
gh issue view "$ISSUE_NUMBER" --repo "$REPOSITORY" --comments > .autobot/input/task-issue-comments.txt 2>/dev/null || true
if [[ -n "$existing_pr_number" ]]; then
  gh pr view "$existing_pr_number" --repo "$REPOSITORY" --comments > .autobot/input/pr-comments.txt 2>/dev/null || true
  gh api "repos/${REPOSITORY}/pulls/${existing_pr_number}/reviews" > .autobot/input/pr-reviews.json 2>/dev/null || true
  python - <<'PY' > .autobot/input/pr-requested-changes.md
import json
from pathlib import Path

path = Path(".autobot/input/pr-reviews.json")
if not path.exists():
    print("No pull request review data found.")
    raise SystemExit(0)
try:
    reviews = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("Pull request review data could not be parsed.")
    raise SystemExit(0)
if not isinstance(reviews, list):
    print("Pull request review data is not a list.")
    raise SystemExit(0)
requested = [r for r in reviews if isinstance(r, dict) and str(r.get("state", "")).upper() == "CHANGES_REQUESTED"]
if not requested:
    print("No CHANGES_REQUESTED reviews were found.")
    raise SystemExit(0)
for review in requested:
    user = (review.get("user") or {}).get("login", "unknown")
    body = str(review.get("body") or "").strip() or "(empty review body)"
    submitted = str(review.get("submitted_at") or "unknown time")
    print(f"- Reviewer @{user} at {submitted}:")
    print(body)
    print("")
PY
fi
cat >> .autobot/input/implement-prompt.md <<EOF

Runtime context:
- Repository: ${REPOSITORY}
- Default branch: ${DEFAULT_BRANCH}
- Task issue: #${ISSUE_NUMBER}
- Implementation branch: ${branch_name}
- Issue context file: .autobot/input/issue.json
- Rework context file: .autobot/input/rework-context.md
- Task issue comments file: .autobot/input/task-issue-comments.txt
- PR requested-changes summary file: .autobot/input/pr-requested-changes.md
- PR comments file: .autobot/input/pr-comments.txt
- Output JSON path: .autobot/output/implement.json
EOF

gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot implementation run started on branch \`${branch_name}\`." >/dev/null
gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label autobot-in-review --remove-label autobot-blocked --add-label "$TRIGGER_LABEL" >/dev/null || true
sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Implementing" || true

git fetch origin "$DEFAULT_BRANCH"
if git ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; then
  git fetch origin "$branch_name"
  git checkout -B "$branch_name" "origin/$branch_name"
else
  git checkout -B "$branch_name" "origin/$DEFAULT_BRANCH"
fi
if [[ "$provider" == "github-copilot" ]]; then
  mkdir -p .autobot/output
  cat > .autobot/output/implement.json <<EOF
{
  "status": "in_progress",
  "blocked_reason": "Copilot handoff initialized; update this artifact to status=completed in the correlated PR.",
  "issue_comment": "",
  "pr_title": "",
  "pr_body": ""
}
EOF
  git add .autobot/output/implement.json
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  if ! git diff --cached --quiet; then
    if ! git commit -m "Initialize Copilot implement handoff for issue #${ISSUE_NUMBER}" >/dev/null 2>&1; then
      blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Failed to create Copilot handoff artifact commit for ${branch_name}." "${WORKFLOW_RUN_URL:-}"
    fi
  fi
  if ! git push --force-with-lease origin "$branch_name" >/dev/null 2>&1; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Failed to publish branch ${branch_name} for Copilot handoff." "${WORKFLOW_RUN_URL:-}"
  fi

  if ! pr_url="$(start_copilot_handoff "implement" "$REPOSITORY" "$ISSUE_NUMBER" "$branch_name" ".autobot/output/implement.json" "${WORKFLOW_RUN_URL:-}" "$TRIGGER_LABEL")"; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Failed to start Copilot implementation handoff." "${WORKFLOW_RUN_URL:-}"
  fi
  gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label autobot-in-review --remove-label autobot-blocked --add-label "$TRIGGER_LABEL" >/dev/null || true
  sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Implementing" || true

  pr_number="${pr_url##*/}"
  wait_minutes_raw="${AUTOBOT_COPILOT_IMPLEMENT_AUTOCOMPLETE_WAIT_MINUTES:-20}"
  if [[ ! "$wait_minutes_raw" =~ ^[0-9]+$ ]]; then
    wait_minutes_raw=20
  fi
  if (( wait_minutes_raw < 1 )); then
    wait_minutes_raw=1
  fi
  if (( wait_minutes_raw > 180 )); then
    wait_minutes_raw=180
  fi

  strict_mode="$(copilot_strict_artifact_mode)"
  autocomplete_deadline=$(( $(date +%s) + wait_minutes_raw * 60 ))
  while true; do
    git fetch origin "$branch_name" >/dev/null 2>&1 || true

    artifact_completed="false"
    if git show "origin/${branch_name}:.autobot/output/implement.json" > .autobot/output/implement-check.json 2>/dev/null; then
      artifact_status="$(python -c "import json;print(str(json.load(open('.autobot/output/implement-check.json','r',encoding='utf-8')).get('status','')).strip().lower())" 2>/dev/null || true)"
      if [[ "$artifact_status" == "completed" ]]; then
        artifact_completed="true"
      fi
    fi

    has_non_autobot_changes="false"
    changed_files="$(git diff --name-only "origin/${DEFAULT_BRANCH}...origin/${branch_name}" | grep -Ev '^(\.autobot/|$)' || true)"
    if [[ -n "$changed_files" ]]; then
      has_non_autobot_changes="true"
    fi

    should_evaluate_completion="false"
    if [[ "$strict_mode" == "true" ]]; then
      if [[ "$artifact_completed" == "true" ]]; then
        should_evaluate_completion="true"
      fi
    else
      if [[ "$artifact_completed" == "true" || "$has_non_autobot_changes" == "true" ]]; then
        should_evaluate_completion="true"
      fi
    fi

    if [[ "$should_evaluate_completion" == "true" ]]; then
      PR_NUMBER="$pr_number" bash "$SCRIPT_DIR/run_copilot_completion_phase.sh" || true
      break
    fi

    now_epoch="$(date +%s)"
    if (( now_epoch >= autocomplete_deadline )); then
      break
    fi
    sleep 60
  done

  printf 'Copilot implementation handoff started with PR: %s\n' "$pr_url"
  rm -rf .autobot
  exit 0
fi

run_phase_provider "implement" ".autobot/input/implement-prompt.md" ".autobot/output/implement.log" ".autobot/output/implement.json" "$REPOSITORY" "$ISSUE_NUMBER" "${WORKFLOW_RUN_URL:-}"
result="$(result_from_log .autobot/output/implement.log)"
summary="$(summary_from_log .autobot/output/implement.log)"
if [[ "$result" != "completed" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "${summary:-Implementation phase returned blocked result.}" "${WORKFLOW_RUN_URL:-}"
fi

if [[ ! -f .autobot/output/implement.json ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Implementation phase did not produce .autobot/output/implement.json." "${WORKFLOW_RUN_URL:-}"
fi

status="$(python -c "import json;print(json.load(open('.autobot/output/implement.json','r',encoding='utf-8')).get('status','').strip().lower())")"
if [[ "$status" != "completed" ]]; then
  reason="$(python -c "import json;print(json.load(open('.autobot/output/implement.json','r',encoding='utf-8')).get('blocked_reason','Implement output status is not completed.'))")"
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "$reason" "${WORKFLOW_RUN_URL:-}"
fi

pr_title="$(python -c "import json;print(json.load(open('.autobot/output/implement.json','r',encoding='utf-8')).get('pr_title','Implement issue #${ISSUE_NUMBER}'))")"
pr_body="$(python -c "import json;print(json.load(open('.autobot/output/implement.json','r',encoding='utf-8')).get('pr_body','Automated implementation for task issue.'))")"
issue_comment="$(python -c "import json;print(json.load(open('.autobot/output/implement.json','r',encoding='utf-8')).get('issue_comment','Implementation pull request is ready for review.'))")"

printf '%s' "$pr_body" > .autobot/output/pr-body.txt
printf '%s' "$issue_comment" > .autobot/output/issue-comment.txt
guard_text_file .autobot/output/pr-body.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "PR body from implementation agent was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"
guard_text_file .autobot/output/issue-comment.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Issue comment from implementation agent was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

if [[ "$provider" == "github-copilot" ]]; then
  pr_url="$(cat .autobot/copilot/pr-url.txt 2>/dev/null || true)"
  if [[ -z "$pr_url" ]]; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Copilot provider completed but no correlated PR URL was recorded." "${WORKFLOW_RUN_URL:-}"
  fi
else
  git add -A
  git restore --staged .autobot >/dev/null 2>&1 || true
  if git diff --cached --quiet; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "No code changes were staged for commit." "${WORKFLOW_RUN_URL:-}"
  fi

  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git commit -m "Implement task issue #${ISSUE_NUMBER}"
  git push --force-with-lease origin "$branch_name"

  pr_number="$(gh pr list --repo "$REPOSITORY" --head "$branch_name" --json number --jq '.[0].number')"
  if [[ -z "$pr_number" ]]; then
    pr_url="$(gh pr create --repo "$REPOSITORY" --base "$DEFAULT_BRANCH" --head "$branch_name" --title "$pr_title" --body-file .autobot/output/pr-body.txt)"
  else
    gh pr edit "$pr_number" --repo "$REPOSITORY" --title "$pr_title" --body-file .autobot/output/pr-body.txt >/dev/null
    pr_url="$(gh pr view "$pr_number" --repo "$REPOSITORY" --json url --jq .url)"
  fi
fi

printf '%s\n\nPull request: %s\n' "$issue_comment" "$pr_url" > .autobot/output/final-comment.txt
guard_text_file .autobot/output/final-comment.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Final implementation comment was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body-file .autobot/output/final-comment.txt >/dev/null
gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" --remove-label autobot-blocked --add-label autobot-in-review >/dev/null || true
sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "In review" || true

rm -rf .autobot

echo "implementation phase completed for issue #${ISSUE_NUMBER}"
