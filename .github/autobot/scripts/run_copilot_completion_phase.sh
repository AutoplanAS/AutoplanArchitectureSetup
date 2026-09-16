#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow_common.sh"

require_cmd gh git python

if [[ -z "${REPOSITORY:-}" || -z "${PR_NUMBER:-}" || -z "${DEFAULT_BRANCH:-}" ]]; then
  echo "missing required environment values" >&2
  exit 1
fi

mkdir -p .autobot/copilot .autobot/output

pr_json_path=".autobot/copilot/pr.json"
gh pr view "$PR_NUMBER" --repo "$REPOSITORY" --json number,title,body,author,assignees,headRefName,baseRefName,url,state,isDraft > "$pr_json_path"

pr_head="$(python -c "import json;print(json.load(open('$pr_json_path','r',encoding='utf-8')).get('headRefName',''))")"
pr_url="$(python -c "import json;print(json.load(open('$pr_json_path','r',encoding='utf-8')).get('url',''))")"
pr_title_current="$(python -c "import json;print(json.load(open('$pr_json_path','r',encoding='utf-8')).get('title',''))")"
pr_body_current="$(python -c "import json;print(json.load(open('$pr_json_path','r',encoding='utf-8')).get('body',''))")"
pr_assignees="$(python -c "import json;print('\n'.join([a.get('login','') for a in json.load(open('$pr_json_path','r',encoding='utf-8')).get('assignees',[]) if a.get('login')]))")"

issue_number=""
if [[ "$pr_head" =~ ^autobot/([0-9]+)- ]]; then
  issue_number="${BASH_REMATCH[1]}"
elif [[ "$pr_head" =~ ^autobot-plan/([0-9]+)- ]]; then
  issue_number="${BASH_REMATCH[1]}"
else
  echo "skip: PR #${PR_NUMBER} head branch does not match autobot handoff pattern."
  exit 0
fi

if [[ -n "${AUTOBOT_COPILOT_ASSIGNEE:-}" ]]; then
  if ! printf '%s\n' "$pr_assignees" | grep -Fxq "$AUTOBOT_COPILOT_ASSIGNEE"; then
    echo "skip: PR assignees do not include AUTOBOT_COPILOT_ASSIGNEE=$AUTOBOT_COPILOT_ASSIGNEE"
    exit 0
  fi
fi

combined_text="$(gh pr view "$PR_NUMBER" --repo "$REPOSITORY" --json body --jq .body 2>/dev/null || true)"
combined_text+=$'\n'
combined_text+="$(gh pr view "$PR_NUMBER" --repo "$REPOSITORY" --comments 2>/dev/null || true)"
run_token="$(printf '%s' "$combined_text" | grep -Eo 'autobot-(spec|plan|implement)-[0-9]+(-[0-9]+)?' | tail -n 1 || true)"
if [[ -z "$run_token" ]]; then
  echo "skip: no autobot token found in PR body/comments."
  exit 0
fi

phase="$(printf '%s' "$run_token" | cut -d'-' -f2)"
token_issue_number="$(printf '%s' "$run_token" | cut -d'-' -f3)"
if [[ "$token_issue_number" != "$issue_number" ]]; then
  echo "skip: run token issue number ($token_issue_number) does not match branch issue number ($issue_number)."
  exit 0
fi

provider="$(provider_for_phase "$phase" 2>/dev/null || true)"
if [[ "$provider" != "github-copilot" ]]; then
  echo "skip: provider for phase '$phase' is '$provider', not github-copilot."
  exit 0
fi

if ! pr_references_issue "$REPOSITORY" "$PR_NUMBER" "$issue_number"; then
  echo "skip: PR #${PR_NUMBER} does not reference issue #${issue_number}."
  exit 0
fi
if ! pr_contains_token "$REPOSITORY" "$PR_NUMBER" "$run_token"; then
  echo "skip: PR #${PR_NUMBER} does not contain run token ${run_token}."
  exit 0
fi

issue_json_path=".autobot/copilot/issue.json"
gh api "repos/${REPOSITORY}/issues/${issue_number}" > "$issue_json_path"
labels="$(issue_labels_from_json "$issue_json_path")"

git fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
git fetch origin "$pr_head" >/dev/null 2>&1 || true
ref="origin/${pr_head}"
artifact_path=".autobot/output/${phase}.json"
artifact_file=".autobot/copilot/provider-${phase}.json"

artifact_status=""
if git show "${ref}:${artifact_path}" > "$artifact_file" 2>/dev/null; then
  artifact_status="$(python -c "import json;print(str(json.load(open('$artifact_file','r',encoding='utf-8')).get('status','')).strip().lower())" 2>/dev/null || true)"
fi

design_path=""
expected_design_path=""
if [[ "$phase" == "spec" ]]; then
  if [[ "$pr_head" =~ ^autobot/(.+)$ ]]; then
    expected_design_path="docs/${BASH_REMATCH[1]}/design.md"
  else
    expected_design_path="docs/${issue_number}-<slug>/design.md"
  fi
  design_path="$(git ls-tree -r --name-only "$ref" | grep -E "^docs/${issue_number}-[^/]+/design\.md$" | head -n 1 || true)"
fi

marker="Autobot ${phase} completion accepted for token \`${run_token}\`."
pending_marker=""
if [[ "$phase" == "spec" ]]; then
  pending_marker="Autobot spec completion pending for token \`${run_token}\`."
fi
issue_comments="$(gh issue view "$issue_number" --repo "$REPOSITORY" --comments 2>/dev/null || true)"

if [[ "$phase" == "spec" ]]; then
  if [[ -z "$design_path" ]]; then
    if [[ -n "$pending_marker" ]] && ! printf '%s' "$issue_comments" | grep -Fq "$pending_marker"; then
      cat > .autobot/output/spec-pending-comment.txt <<EOF
Autobot spec completion is still waiting for the design document.

- Expected design file path in this PR branch: \`${expected_design_path}\`
- Current state: no \`docs/${issue_number}-*/design.md\` file found in branch \`${pr_head}\`
- Required: add the design markdown file, then update the PR (push commit or comment)

${pending_marker}
EOF
      if guard_text_file .autobot/output/spec-pending-comment.txt; then
        gh issue comment "$issue_number" --repo "$REPOSITORY" --body-file .autobot/output/spec-pending-comment.txt >/dev/null || true
      else
        gh issue comment "$issue_number" --repo "$REPOSITORY" --body "Autobot spec completion is waiting for design content in \`${expected_design_path}\` (${pending_marker})." >/dev/null || true
      fi
    fi
    echo "skip: spec completion requires docs/${issue_number}-*/design.md in the handoff PR."
    exit 0
  fi

  git show "${ref}:${design_path}" > .autobot/output/spec-design.md 2>/dev/null || true
  if grep -Eq '^[[:space:]]*Autobot Copilot handoff placeholder\.[[:space:]]*$' .autobot/output/spec-design.md 2>/dev/null; then
    if [[ -n "$pending_marker" ]] && ! printf '%s' "$issue_comments" | grep -Fq "$pending_marker"; then
      cat > .autobot/output/spec-pending-comment.txt <<EOF
Autobot spec completion is still waiting for real design content.

- Required design file: \`${design_path}\`
- Current state: file still contains placeholder handoff text
- Required: replace placeholder text with the final design, then update the PR

${pending_marker}
EOF
      if guard_text_file .autobot/output/spec-pending-comment.txt; then
        gh issue comment "$issue_number" --repo "$REPOSITORY" --body-file .autobot/output/spec-pending-comment.txt >/dev/null || true
      else
        gh issue comment "$issue_number" --repo "$REPOSITORY" --body "Autobot spec completion is waiting for non-placeholder design content in \`${design_path}\` (${pending_marker})." >/dev/null || true
      fi
    fi
    echo "skip: spec design file still contains placeholder handoff text."
    exit 0
  fi
  if ! grep -q '[^[:space:]]' .autobot/output/spec-design.md 2>/dev/null; then
    echo "skip: spec design file is empty and must contain final design content."
    exit 0
  fi
fi

strict_mode="$(copilot_strict_artifact_mode)"
if [[ "$artifact_status" != "completed" ]]; then
  if [[ "$strict_mode" == "true" || "$phase" == "spec" ]]; then
    if [[ "$phase" == "spec" ]]; then
      echo "skip: spec completion requires ${artifact_path} status=completed with completion-ready metadata."
    else
      echo "skip: strict artifact mode requires ${artifact_path} status=completed."
    fi
    exit 0
  fi

  if [[ "$phase" == "implement" ]]; then
    changed_files="$(git diff --name-only "origin/${DEFAULT_BRANCH}...${ref}" | grep -Ev '^(\.autobot/|$)' || true)"
    if [[ -z "$changed_files" ]]; then
      echo "skip: relaxed mode still requires non-.autobot changes for implement completion."
      exit 0
    fi
    python - "$artifact_file" "$pr_title_current" "$pr_body_current" <<'PY'
import json
import pathlib
import sys
payload = {
    "status": "completed",
    "issue_comment": "Implementation pull request is ready for review.",
    "pr_title": sys.argv[2],
    "pr_body": sys.argv[3],
    "blocked_reason": "",
}
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload), encoding="utf-8")
PY
  else
    echo "skip: plan phase requires completed artifact payload."
    exit 0
  fi
fi

if [[ "$phase" == "spec" ]]; then
  if ! spec_artifact_reason="$(python - "$artifact_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
issue_comment = str(payload.get("issue_comment", "")).strip()
pr_title = str(payload.get("pr_title", "")).strip()
pr_body = str(payload.get("pr_body", "")).strip()
blocked_reason = str(payload.get("blocked_reason", "")).strip()

if not issue_comment:
    print("issue_comment must be non-empty when status=completed.")
    sys.exit(1)
if not pr_title:
    print("pr_title must be non-empty when status=completed.")
    sys.exit(1)
if not pr_body:
    print("pr_body must be non-empty when status=completed.")
    sys.exit(1)
if blocked_reason:
    print("blocked_reason must be empty when status=completed.")
    sys.exit(1)
PY
  )"; then
    if [[ -z "${spec_artifact_reason//[[:space:]]/}" ]]; then
      spec_artifact_reason="spec.json is invalid or missing required completion fields."
    fi
    echo "skip: spec completion requires completion-ready metadata in ${artifact_path} (${spec_artifact_reason})"
    exit 0
  fi
fi

if printf '%s' "$issue_comments" | grep -Fq "$marker"; then
  echo "skip: completion already accepted for token ${run_token}."
  exit 0
fi

if [[ "$phase" == "spec" ]]; then
  issue_comment="$(python -c "import json;print(json.load(open('$artifact_file','r',encoding='utf-8')).get('issue_comment','Design draft is ready for review.'))")"
  if [[ -z "${issue_comment//[[:space:]]/}" ]]; then
    issue_comment="Design draft is ready for review."
  fi
  pr_title="$(python -c "import json;print(json.load(open('$artifact_file','r',encoding='utf-8')).get('pr_title',''))")"
  pr_body="$(python -c "import json;print(json.load(open('$artifact_file','r',encoding='utf-8')).get('pr_body',''))")"
  design_url=""
  if [[ -n "$design_path" ]]; then
    design_url="https://github.com/${REPOSITORY}/blob/${pr_head}/${design_path}"
  fi
  spec_design_local=".autobot/output/spec-design.md"
  if [[ -n "$design_path" ]]; then
    git show "${ref}:${design_path}" > "$spec_design_local" 2>/dev/null || true
  fi
  publish_spec_artifacts "$REPOSITORY" "$issue_number" "$pr_head" "$spec_design_local"
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

  if [[ -n "$pr_title" ]]; then
    printf '%s' "$pr_body" > .autobot/output/correlation-pr-body.txt
    guard_text_file .autobot/output/correlation-pr-body.txt || blocked_and_exit "$REPOSITORY" "$issue_number" autobot-ready-for-spec "PR body from Copilot completion was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"
    gh pr edit "$PR_NUMBER" --repo "$REPOSITORY" --title "$pr_title" --body-file .autobot/output/correlation-pr-body.txt >/dev/null || true
  fi

  if [[ -n "$design_url" ]]; then
    cat > .autobot/output/correlation-issue-comment.txt <<EOF
${issue_comment}

Design file: [${design_path}](${design_url})
Design pull request: ${pr_url}
${artifact_links_block}
${artifact_warning_block}

Next step: review and merge the design pull request to approve the specification. After merge, add \`autobot-ready-to-implement\` on this feature issue to start planning.

${marker}
EOF
  else
    cat > .autobot/output/correlation-issue-comment.txt <<EOF
${issue_comment}

Design pull request: ${pr_url}
${artifact_links_block}
${artifact_warning_block}

Next step: review and merge the design pull request to approve the specification. After merge, add \`autobot-ready-to-implement\` on this feature issue to start planning.

${marker}
EOF
  fi
  guard_text_file .autobot/output/correlation-issue-comment.txt || blocked_and_exit "$REPOSITORY" "$issue_number" autobot-ready-for-spec "Issue comment from Copilot completion was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

  gh issue comment "$issue_number" --repo "$REPOSITORY" --body-file .autobot/output/correlation-issue-comment.txt >/dev/null
  gh issue edit "$issue_number" --repo "$REPOSITORY" --remove-label autobot-ready-for-spec --remove-label autobot-creating-specification --remove-label autobot-blocked --add-label autobot-review-specification >/dev/null || true
  sync_project_stage_with_warning "$REPOSITORY" "$issue_number" "Review specification" || true
  echo "accepted spec completion for issue #${issue_number} from PR #${PR_NUMBER}"
  exit 0
fi

if [[ "$phase" == "plan" ]]; then
  design_path="$(git ls-tree -r --name-only "origin/${DEFAULT_BRANCH}" | grep -E "^docs/${issue_number}-[^/]+/design\.md$" | head -n 1 || true)"
  if [[ -z "$design_path" ]]; then
    design_path="docs/${issue_number}-unknown/design.md"
  fi
  cp "$artifact_file" .autobot/output/plan.json
  python "$SCRIPT_DIR/create_plan_issues.py" \
    --repo "$REPOSITORY" \
    --feature-issue "$issue_number" \
    --plan-json .autobot/output/plan.json \
    --default-branch "$DEFAULT_BRANCH" \
    --design-path "$design_path" \
    --project-owner "${PROJECT_OWNER:-}" \
    --project-number "${PROJECT_NUMBER:-}" \
    --project-status-field "${PROJECT_STATUS_FIELD:-Status}" \
    > .autobot/output/created-plan.json

  feature_comment="$(python -c "import json;print(json.load(open('.autobot/output/created-plan.json','r',encoding='utf-8')).get('feature_comment','Plan completed.'))")"
  close_comment="$(python -c "import json;print(json.load(open('.autobot/output/created-plan.json','r',encoding='utf-8')).get('close_comment',''))")"
  printf '%s\n\nSource planning PR: %s\n\n%s\n' "$feature_comment" "$pr_url" "$marker" > .autobot/output/correlation-feature-comment.txt
  guard_text_file .autobot/output/correlation-feature-comment.txt || blocked_and_exit "$REPOSITORY" "$issue_number" autobot-ready-to-implement "Feature comment from Copilot plan completion was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

  gh issue comment "$issue_number" --repo "$REPOSITORY" --body-file .autobot/output/correlation-feature-comment.txt >/dev/null
  gh issue edit "$issue_number" --repo "$REPOSITORY" --remove-label autobot-ready-to-implement --remove-label autobot-blocked >/dev/null || true
  if [[ -n "${close_comment//[[:space:]]/}" ]]; then
    gh issue close "$issue_number" --repo "$REPOSITORY" --reason completed --comment "$close_comment" >/dev/null || true
  else
    gh issue close "$issue_number" --repo "$REPOSITORY" --reason completed >/dev/null || true
  fi
  sync_project_stage_with_warning "$REPOSITORY" "$issue_number" "Done" || true
  echo "accepted plan completion for issue #${issue_number} from PR #${PR_NUMBER}"
  exit 0
fi

if [[ "$phase" == "implement" ]]; then
  issue_comment="$(python -c "import json;print(json.load(open('$artifact_file','r',encoding='utf-8')).get('issue_comment','Implementation pull request is ready for review.'))")"
  pr_title="$(python -c "import json;print(json.load(open('$artifact_file','r',encoding='utf-8')).get('pr_title',''))")"
  pr_body="$(python -c "import json;print(json.load(open('$artifact_file','r',encoding='utf-8')).get('pr_body',''))")"

  if [[ -n "$pr_title" ]]; then
    printf '%s' "$pr_body" > .autobot/output/correlation-pr-body.txt
    guard_text_file .autobot/output/correlation-pr-body.txt || blocked_and_exit "$REPOSITORY" "$issue_number" autobot-implementing "PR body from Copilot implementation completion was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"
    gh pr edit "$PR_NUMBER" --repo "$REPOSITORY" --title "$pr_title" --body-file .autobot/output/correlation-pr-body.txt >/dev/null || true
  fi

  printf '%s\n\nPull request: %s\n\n%s\n' "$issue_comment" "$pr_url" "$marker" > .autobot/output/correlation-issue-comment.txt
  guard_text_file .autobot/output/correlation-issue-comment.txt || blocked_and_exit "$REPOSITORY" "$issue_number" autobot-implementing "Issue comment from Copilot implementation completion was blocked by secret guard." "${WORKFLOW_RUN_URL:-}"

  gh issue comment "$issue_number" --repo "$REPOSITORY" --body-file .autobot/output/correlation-issue-comment.txt >/dev/null
  gh issue edit "$issue_number" --repo "$REPOSITORY" --remove-label autobot-implementing --remove-label autobot-blocked --add-label autobot-in-review >/dev/null || true
  sync_project_stage_with_warning "$REPOSITORY" "$issue_number" "In review" || true
  echo "accepted implement completion for issue #${issue_number} from PR #${PR_NUMBER}"
  exit 0
fi

echo "skip: unsupported phase '${phase}' from token ${run_token}."
