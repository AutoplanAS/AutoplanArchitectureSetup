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
ensure_provider_valid_or_block "spec" "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "${WORKFLOW_RUN_URL:-}"

if [[ "$(actor_has_write_access "$REPOSITORY" "$ACTOR")" != "true" ]]; then
  gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot ignored the label because @$ACTOR does not have write access to this repository." >/dev/null
  gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" >/dev/null || true
  exit 0
fi

provider="$(provider_for_phase spec)"
if [[ "$provider" == "codex" && -z "${CODEX_API_KEY:-}" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Missing CODEX_API_KEY. Grant the org-level secret to this repository before retrying." "${WORKFLOW_RUN_URL:-}"
fi

mkdir -p .autobot/input .autobot/output
gh api "repos/${REPOSITORY}/issues/${ISSUE_NUMBER}" > .autobot/input/issue.json

title="$(issue_title_from_json .autobot/input/issue.json)"
slug="$(slugify "$title")"
branch_name="autobot/${ISSUE_NUMBER}-${slug}"
design_path="docs/${ISSUE_NUMBER}-${slug}/design.md"
design_url="https://github.com/${REPOSITORY}/blob/${branch_name}/${design_path}"

cat "$SCRIPT_DIR/../prompts/spec.md" > .autobot/input/spec-prompt.md
cat >> .autobot/input/spec-prompt.md <<EOF

Runtime context:
- Repository: ${REPOSITORY}
- Default branch: ${DEFAULT_BRANCH}
- Feature issue: #${ISSUE_NUMBER}
- Design path: ${design_path}
- Design URL: ${design_url}
- Issue context file: .autobot/input/issue.json
- Output JSON path: .autobot/output/spec.json
EOF

gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body "Autobot spec run started on branch \`${branch_name}\`." >/dev/null
sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Ready for spec" || true

git fetch origin "$DEFAULT_BRANCH"
git checkout -B "$branch_name" "origin/$DEFAULT_BRANCH"
if [[ "$provider" == "github-copilot" ]]; then
  mkdir -p .autobot/output
  cat > .autobot/output/spec.json <<EOF
{
  "status": "in_progress",
  "blocked_reason": "Copilot handoff initialized; create ${design_path} and update this artifact to status=completed in the correlated PR (required when strict artifact mode is enabled).",
  "issue_comment": "",
  "pr_title": "",
  "pr_body": ""
}
EOF
  git add .autobot/output/spec.json
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  if ! git diff --cached --quiet; then
    if ! git commit -m "Initialize Copilot spec handoff for issue #${ISSUE_NUMBER}" >/dev/null 2>&1; then
      blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Failed to create Copilot handoff artifact commit for ${branch_name}." "${WORKFLOW_RUN_URL:-}"
    fi
  fi
  if ! git push --force-with-lease origin "$branch_name" >/dev/null 2>&1; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Failed to publish branch ${branch_name} for Copilot handoff." "${WORKFLOW_RUN_URL:-}"
  fi

  if ! pr_url="$(start_copilot_handoff "spec" "$REPOSITORY" "$ISSUE_NUMBER" "$branch_name" ".autobot/output/spec.json" "${WORKFLOW_RUN_URL:-}" "$TRIGGER_LABEL" "$design_path")"; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Failed to start Copilot spec handoff." "${WORKFLOW_RUN_URL:-}"
  fi
  gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" --remove-label autobot-review-specification --remove-label autobot-blocked --add-label autobot-creating-specification >/dev/null || true
  sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Creating specification" || true
  printf 'Copilot spec handoff started with PR: %s\n' "$pr_url"
  rm -rf .autobot
  exit 0
fi

run_phase_provider "spec" ".autobot/input/spec-prompt.md" ".autobot/output/spec.log" ".autobot/output/spec.json" "$REPOSITORY" "$ISSUE_NUMBER" "${WORKFLOW_RUN_URL:-}"
result="$(result_from_log .autobot/output/spec.log)"
summary="$(summary_from_log .autobot/output/spec.log)"

if [[ "$result" != "completed" ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "${summary:-Spec phase returned blocked result.}" "${WORKFLOW_RUN_URL:-}"
fi

if [[ ! -f .autobot/output/spec.json ]]; then
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Spec phase did not produce .autobot/output/spec.json." "${WORKFLOW_RUN_URL:-}"
fi

status="$(python -c "import json;print(json.load(open('.autobot/output/spec.json','r',encoding='utf-8')).get('status','').strip().lower())")"
if [[ "$status" != "completed" ]]; then
  reason="$(python -c "import json;print(json.load(open('.autobot/output/spec.json','r',encoding='utf-8')).get('blocked_reason','Spec output status is not completed.'))")"
  blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "$reason" "${WORKFLOW_RUN_URL:-}"
fi

issue_comment="$(python -c "import json;print(json.load(open('.autobot/output/spec.json','r',encoding='utf-8')).get('issue_comment','Design draft is ready for review.'))")"
pr_title="$(python -c "import json;print(json.load(open('.autobot/output/spec.json','r',encoding='utf-8')).get('pr_title','Spec: design for issue #${ISSUE_NUMBER}'))")"
pr_body="$(python -c "import json;print(json.load(open('.autobot/output/spec.json','r',encoding='utf-8')).get('pr_body','Automated design proposal generated by autobot spec phase.'))")"

printf '%s' "$issue_comment" > .autobot/output/issue-comment.txt
printf '%s' "$pr_body" > .autobot/output/pr-body.txt
guard_text_file .autobot/output/issue-comment.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Issue comment from agent was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"
guard_text_file .autobot/output/pr-body.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "PR body from agent was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

if [[ "$provider" == "codex" ]]; then
  if [[ ! -f "$design_path" ]]; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Expected design file was not written: ${design_path}" "${WORKFLOW_RUN_URL:-}"
  fi

  git add "$design_path"
  if git diff --cached --quiet; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "No design changes were staged for commit." "${WORKFLOW_RUN_URL:-}"
  fi

  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git commit -m "Add spec design for issue #${ISSUE_NUMBER}"
  git push --force-with-lease origin "$branch_name"
fi

if [[ "$provider" == "github-copilot" ]]; then
  pr_url="$(cat .autobot/copilot/pr-url.txt 2>/dev/null || true)"
  if [[ -z "$pr_url" ]]; then
    blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Copilot provider completed but no correlated PR URL was recorded." "${WORKFLOW_RUN_URL:-}"
  fi
else
  pr_number="$(gh pr list --repo "$REPOSITORY" --head "$branch_name" --json number --jq '.[0].number')"
  if [[ -z "$pr_number" ]]; then
    pr_url="$(gh pr create --repo "$REPOSITORY" --base "$DEFAULT_BRANCH" --head "$branch_name" --title "$pr_title" --body-file .autobot/output/pr-body.txt)"
  else
    gh pr edit "$pr_number" --repo "$REPOSITORY" --title "$pr_title" --body-file .autobot/output/pr-body.txt >/dev/null
    pr_url="$(gh pr view "$pr_number" --repo "$REPOSITORY" --json url --jq .url)"
  fi
fi

publish_spec_artifacts "$REPOSITORY" "$ISSUE_NUMBER" "$branch_name" "$design_path"
artifact_warning_block=""
if [[ -n "${SPEC_ARTIFACTS_WARNING:-}" ]]; then
  artifact_warning_block=$(
    cat <<EOF

Autobot warning: ${SPEC_ARTIFACTS_WARNING}
Run: ${WORKFLOW_RUN_URL:-}
EOF
  )
fi
artifact_links_block=""
if [[ -n "${SPEC_ARTIFACTS_LINKS_MARKDOWN:-}" ]]; then
  artifact_links_block=$(
    cat <<EOF

${SPEC_ARTIFACTS_LINKS_MARKDOWN}
EOF
  )
fi

cat > .autobot/output/final-comment.txt <<EOF
${issue_comment}

Design file: [${design_path}](${design_url})
Design pull request: ${pr_url}
${artifact_links_block}
${artifact_warning_block}

Next step: review and merge the design pull request to approve the specification. After merge, add \`autobot-ready-to-implement\` on this feature issue to start planning.
EOF
guard_text_file .autobot/output/final-comment.txt || blocked_and_exit "$REPOSITORY" "$ISSUE_NUMBER" "$TRIGGER_LABEL" "Final issue comment was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

gh issue comment "$ISSUE_NUMBER" --repo "$REPOSITORY" --body-file .autobot/output/final-comment.txt >/dev/null
gh issue edit "$ISSUE_NUMBER" --repo "$REPOSITORY" --remove-label "$TRIGGER_LABEL" --remove-label autobot-creating-specification --remove-label autobot-blocked --add-label autobot-review-specification >/dev/null || true
sync_project_stage_with_warning "$REPOSITORY" "$ISSUE_NUMBER" "Review specification" || true

echo "spec phase completed for issue #${ISSUE_NUMBER}"
