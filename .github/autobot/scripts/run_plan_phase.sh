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
ensure_provider_valid_or_block "plan" "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "${WORKFLOW_RUN_URL:-}"

if [[ "$(actor_has_write_access "$REPOSITORY" "$ACTOR")" != "true" ]]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot ignored the label because @$ACTOR does not have write access to this repository." >/dev/null
  gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" >/dev/null || true
  exit 0
fi

provider="$(provider_for_phase plan)"
if [[ "$provider" == "codex" && -z "${CODEX_API_KEY:-}" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Missing CODEX_API_KEY. Grant the org-level secret to this repository before retrying." "${WORKFLOW_RUN_URL:-}"
fi

mkdir -p .autobot/input .autobot/output
gh api "repos/${REPOSITORY}/issues/${ISSUE_NUMBER}" > .autobot/input/issue.json

git fetch origin "$DEFAULT_BRANCH"

design_path="$(git ls-tree -r --name-only "origin/$DEFAULT_BRANCH" | grep -E "^docs/${ISSUE_NUMBER}-[^/]+/design\.md$" | head -n 1 || true)"
if [[ -z "$design_path" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "No merged design file found on ${DEFAULT_BRANCH} for this feature issue." "${WORKFLOW_RUN_URL:-}"
fi

git checkout "origin/$DEFAULT_BRANCH" -- "$design_path"

cat "$SCRIPT_DIR/../prompts/plan.md" > .autobot/input/plan-prompt.md
cat >> .autobot/input/plan-prompt.md <<EOF

Runtime context:
- Repository: ${REPOSITORY}
- Default branch: ${DEFAULT_BRANCH}
- Feature issue: #${ISSUE_NUMBER}
- Merged design file: ${design_path}
- Issue context file: .autobot/input/issue.json
- Output JSON path: .autobot/output/plan.json
EOF

gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot planning run started for merged design \`${design_path}\`." >/dev/null
sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Ready to implement" || true

run_phase_provider "plan" ".autobot/input/plan-prompt.md" ".autobot/output/plan.log" ".autobot/output/plan.json" "$REPOSITORY" "$ISSUE_NUMBER" "${WORKFLOW_RUN_URL:-}"
result="$(result_from_log .autobot/output/plan.log)"
summary="$(summary_from_log .autobot/output/plan.log)"
if [[ "$result" != "completed" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "${summary:-Planning phase returned blocked result.}" "${WORKFLOW_RUN_URL:-}"
fi

if [[ ! -f .autobot/output/plan.json ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Planning phase did not produce .autobot/output/plan.json." "${WORKFLOW_RUN_URL:-}"
fi

status="$(python -c "import json;print(json.load(open('.autobot/output/plan.json','r',encoding='utf-8')).get('status','').strip().lower())")"
if [[ "$status" != "completed" ]]; then
  reason="$(python -c "import json;print(json.load(open('.autobot/output/plan.json','r',encoding='utf-8')).get('blocked_reason','Plan output status is not completed.'))")"
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "$reason" "${WORKFLOW_RUN_URL:-}"
fi

python "$SCRIPT_DIR/create_plan_issues.py" \
  --repo "$REPOSITORY" \
  --feature-issue "$ISSUE_NUMBER" \
  --plan-json .autobot/output/plan.json \
  --project-owner "${PROJECT_OWNER:-}" \
  --project-number "${PROJECT_NUMBER:-}" \
  --project-status-field "${PROJECT_STATUS_FIELD:-Status}" \
  > .autobot/output/created-plan.json
feature_comment="$(python -c "import json;print(json.load(open('.autobot/output/created-plan.json','r',encoding='utf-8')).get('feature_comment','Plan completed.'))")"
printf '%s' "$feature_comment" > .autobot/output/feature-comment.txt
guard_text_file .autobot/output/feature-comment.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Feature comment from planner was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body-file .autobot/output/feature-comment.txt >/dev/null
gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" --remove-label autobot-blocked >/dev/null || true
sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Ready to implement" || true

echo "plan phase completed for issue #${ISSUE_NUMBER}"
