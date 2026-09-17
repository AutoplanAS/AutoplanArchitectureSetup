# Autobot GitHub Actions pipeline

This package provides a label-triggered middle ground between manual delivery and full Machinist
autonomy. It keeps human approval between phases and uses reusable GitHub Actions workflows to run
the agent work.

## Included workflows

| Workflow | Type | Purpose |
|---|---|---|
| `.github/workflows/autobot-spec.yml` | Reusable | Generate design PR from feature issue |
| `.github/workflows/autobot-plan.yml` | Reusable | Create task issues from merged design |
| `.github/workflows/autobot-implement.yml` | Reusable | Implement one task issue into one PR |
| `.github/workflows/autobot-copilot-complete.yml` | Reusable | Evaluate Copilot handoff PR updates and apply phase side effects |
| `.github/workflows/autobot-complete.yml` | Reusable | Complete the task and sync Done after its implementation PR merges |
| `.github/workflows/autobot-pr-issue.yml` | Reusable | Resolve the PR's issue number before acquiring its lifecycle lock |
| `.github/workflows/autobot-project-sync.yml` | Reusable | Add issue to project and set stage/status field |
| `.github/workflows/autobot-setup.yml` | Dispatch | Create or refresh required labels |
| `.github/workflows/autobot.yml` | Router | Label + pull-request event router for this repository |
| `.github/workflows/autobot-tests.yml` | CI | Run completion regression tests and phase script syntax checks |

## Label contract

| Label | Trigger | Outcome |
|---|---|---|
| `autobot-ready-for-spec` | Spec phase starts | Codex: direct design PR and move to `autobot-review-specification`. Copilot: handoff PR + `autobot-creating-specification`, then `autobot-review-specification` on completion |
| `autobot-ready-to-implement` | Plan phase starts | Create or reuse main feature issue, create task issues, then close the original specification issue as superseded |
| `autobot-implementing` | Implement phase starts | Codex: direct task PR updates. Copilot: handoff PR, then completion moves task to `autobot-in-review` |
| `autobot-creating-specification` | No | Specification work is in progress |
| `autobot-review-specification` | No | Human review/rework gate before planning |
| `autobot-task` | No | Marks issue as implementation task |
| `autoboot` | No | Compatibility task marker label for autobot-generated tasks |
| `autobot-in-review` | No | Human PR review gate for completed implementation |
| `autobot-done` | No | Implementation PR merged; task closed as completed |
| `autobot-blocked` | No | Phase needs human decision |

## Provider-agnostic workflow (implemented)

The Codex and GitHub Copilot providers use the same lifecycle semantics:

1. Human labels a feature issue `autobot-ready-for-spec`.
2. Autobot starts specification, sets `autobot-creating-specification`, and generates/updates a design PR.
3. When spec output is ready, Autobot sets `autobot-review-specification` and posts canonical design links (plus external spec artifact links when enabled).
4. Human reviews the spec:
   - for rework: comment and relabel `autobot-ready-for-spec`;
   - for approval: label `autobot-ready-to-implement`.
5. Autobot planning runs on the original approved-spec issue.
6. Planning creates or reuses a new **main feature** issue, creates/reuses linked `autobot-task` issues, and keeps work in **Ready to implement**.
7. After successful rollover, Autobot closes the original specification issue as superseded by the main feature issue.
8. Human selects a task for coding by labeling that task issue `autobot-implementing`.
9. Autobot implements on deterministic branch/PR, then sets `autobot-in-review` when ready for human PR review.
10. If PR changes are requested, reviewer feedback does not auto-restart implementation; a human must reapply `autobot-implementing` on the task issue.
11. A human approves and merges the implementation PR into the default branch. Autobot replaces phase labels with `autobot-done`, closes the task as completed, and directly syncs its project stage to **Done**.

## Hard constraints

- No automatic phase skipping across human gates.
- `autobot-in-review` never triggers implementation. Only a merged implementation PR advances the task to `autobot-done`.
- Approval alone and closing a PR without merging do not complete tasks. The merge handler never approves or merges PRs.
- Required human approval is enforced by default-branch protection/rulesets, not by counting historical PR approvals.
- Completing one task does not complete its parent feature or other referenced issues.
- Implementation rework is label-driven only (manual relabel required).
- Rework uses the same implementation branch and PR for the task issue.
- Entering a phase removes stale conflicting phase-state labels.
- External artifact publishing is spec-only in this increment (`design.md`, `design.html`, and branch-scoped `latest.json` pointer).
- External spec artifacts are optional and non-blocking; canonical repository/PR links remain source of truth.

## Required secrets

- `CODEX_API_KEY` (required only for phases configured with provider `codex`)
- `BASELINE_REPO_TOKEN` (optional; required only if this baseline repository is private)
- `AUTOBOT_PROJECT_TOKEN` (required for organization-owned project boards such as `AutoplanAS#8`)
- `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS` (optional; required only when `AUTOBOT_SPEC_ARTIFACTS_ENABLED=true`)
- `AUTOBOT_SPEC_ARTIFACTS_READ_SAS` (optional; required only when `AUTOBOT_SPEC_ARTIFACTS_ENABLED=true`)
- `AUTOBOT_COPILOT_TRIGGER_TOKEN` (optional; PAT used to post Copilot handoff `@copilot` instruction comments as a human account when bot-originated mentions are ignored; if unset, `BASELINE_REPO_TOKEN` is used when available)

When Codex is used, `CODEX_API_KEY` should be managed as an org-level secret and granted to each
adopting repository.

### Obtaining `CODEX_API_KEY`

1. Sign in to your Codex provider API account (for example, OpenAI) with API access enabled.
2. Create a new API key in the provider portal and copy it immediately (most portals show it once).
3. In GitHub org settings, open **Secrets and variables -> Actions** and create an organization secret
   named `CODEX_API_KEY`.
4. Grant the secret to each repository that adopts this pipeline.

Do not commit API keys to the repository. For rotation, create a new provider key, update the
organization secret, then revoke the old key.

### Obtaining `AUTOBOT_PROJECT_TOKEN`

Use a dedicated bot account or maintainer account PAT, then store it as a repository secret.

Fine-grained PAT (recommended):

1. GitHub -> **Settings** -> **Developer settings** -> **Personal access tokens** -> **Fine-grained tokens**.
2. Create a token with:
   - **Resource owner**: your org (for example `AutoplanAS`)
   - **Repository access**: the target repository (or all repos that run this workflow)
   - **Organization permissions**: **Projects = Read and write**
   - **Repository permissions**: at least **Issues = Read** (Write recommended)
3. If your org enforces SSO, authorize the token for the org.
4. In the target repository, set **Settings -> Secrets and variables -> Actions -> New repository secret**:
   - **Name**: `AUTOBOT_PROJECT_TOKEN`
   - **Value**: the PAT

Classic PAT fallback:

- Minimum scopes: `repo`, `project`, `read:org`
- SSO authorization is still required when the org enforces it.

### Codex runtime on GitHub Actions

Autobot runs Codex in non-interactive mode with `--sandbox workspace-write --approve-for-me`.
If GitHub-hosted runner sandboxing fails during bootstrap (for example `bwrap ... Operation not permitted`),
Autobot retries once with `--dangerously-bypass-approvals-and-sandbox` so the phase can still run
inside the runner's own isolation boundary.

Project sync uses repository variables:

- `AUTOBOT_PROJECT_OWNER` (for example `AutoplanAS`)
- `AUTOBOT_PROJECT_NUMBER` (for example `8`)
- `AUTOBOT_PROJECT_STATUS_FIELD` (optional, defaults to `Status`)

Provider routing uses repository variables:

- `AUTOBOT_SPEC_PROVIDER` (`codex` or `github-copilot`, default `codex`)
- `AUTOBOT_PLAN_PROVIDER` (`codex` or `github-copilot`, default `codex`)
- `AUTOBOT_IMPLEMENT_PROVIDER` (`codex` or `github-copilot`, default `codex`)
- `AUTOBOT_COPILOT_ASSIGNEE` (required when any phase uses `github-copilot`; must be a real assignable GitHub login in the target repository)
- `AUTOBOT_COPILOT_TRIGGER_HANDLE` (optional, defaults to `@copilot`; mention used in Copilot handoff PR instruction comments)
- `AUTOBOT_COPILOT_SPEC_AUTOCOMPLETE_WAIT_MINUTES` (optional, defaults to `20`, max `180`; how long the issue-triggered spec job waits and self-runs completion checks)
- `AUTOBOT_COPILOT_PLAN_AUTOCOMPLETE_WAIT_MINUTES` (optional, defaults to `20`, max `180`; how long the issue-triggered plan job waits and self-runs completion checks)
- `AUTOBOT_COPILOT_IMPLEMENT_AUTOCOMPLETE_WAIT_MINUTES` (optional, defaults to `20`, max `180`; how long the issue-triggered implement job waits and self-runs completion checks)
- `AUTOBOT_COPILOT_TIMEOUT_MINUTES` (optional handoff SLA hint in comments, default `90`, max `360`)
- `AUTOBOT_COPILOT_STRICT_ARTIFACT` (`true`/`false`, default `false`; strict mode requires explicit completed phase artifact payloads before acceptance)

Spec artifact publishing uses repository variables:

- `AUTOBOT_SPEC_ARTIFACTS_ENABLED` (`true`/`false`, default `false`)
- `AUTOBOT_SPEC_ARTIFACTS_STORAGE_ACCOUNT` (required when enabled)
- `AUTOBOT_SPEC_ARTIFACTS_CONTAINER` (required when enabled)
- `AUTOBOT_SPEC_ARTIFACTS_PREFIX` (optional, defaults to `autobot-spec`)
- `AUTOBOT_SPEC_ARTIFACTS_ENDPOINT_SUFFIX` (optional, defaults to `blob.core.windows.net`)

Spec artifact path contract:

- Prefix root: `autobot-spec/<owner>/<repo>/<branch>/issue-<issue-number>/`
- Immutable run artifacts:
  - `runs/<run-id>/design.md`
  - `runs/<run-id>/design.html`
- Branch-scoped pointer:
  - `latest.json` (same prefix)

Baseline source selection (optional) uses repository variables:

- `AUTOBOT_BASELINE_REPOSITORY` (defaults to `AutoplanAS/AutoplanArchitectureSetup`)
- `AUTOBOT_BASELINE_REF` (defaults to `v1`; set to a branch, tag, or commit that exists in the baseline repository)

## Adopting in another repository

1. Add labels using this repository's setup workflow:
   - Run `autobot-setup` in this repo and set `target_repository=owner/repo`.
2. Add caller workflow:
   - Copy `.github/autobot/examples/autobot.yml` into target repo as `.github/workflows/autobot.yml`.
3. Grant secrets in target repository:
   - `CODEX_API_KEY` (only needed for phases that use provider `codex`)
   - `BASELINE_REPO_TOKEN` only if needed.
   - `AUTOBOT_PROJECT_TOKEN` when project scope permissions are required.
   - `AUTOBOT_COPILOT_TRIGGER_TOKEN` (optional, recommended when any phase uses `github-copilot`)
   - `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS` and `AUTOBOT_SPEC_ARTIFACTS_READ_SAS` when spec artifact publishing is enabled.
4. Configure provider routing variables for your preferred execution model.
5. Require human PR approval on the default branch using branch protection or a ruleset, including dismissal of stale approvals and restrictions on bypass. Without this policy, a bypassed/unreviewed merge is still treated as merged by the completion handler.
6. Ensure the configured project status field has a **Done** option. Existing consumers must copy the updated router and use a workflow release and `AUTOBOT_BASELINE_REF` containing `autobot-complete.yml` and `complete_merged_pr.py`. An older `v1` tag must be updated/published before consumers can use this addition.

## Merge completion and recovery

The router handles `pull_request_target: closed` using default-branch workflow configuration.
The merge job only checks out trusted baseline tooling, never the PR head or consumer code.
It reads current PR metadata from GitHub and accepts only a merged PR into the default branch
whose head belongs to the same repository and follows `autobot/<task-issue-number>-<slug>`.
Both providers already use this deterministic branch contract. The referenced issue must have
`autobot-task` and either `autobot-in-review` or `autobot-done`; spec, planning, parent-feature,
fork, and unrelated PRs are ignored. PR-body issue mentions do not select completion targets.

The handler preserves non-phase labels, including `autobot-task` and `autoboot`. It also works
when GitHub closing keywords have already closed the task. Every accepted invocation syncs
the project directly, because `GITHUB_TOKEN` label/closure writes do not trigger another
Actions run. The project token is used only for project commands; issue writes use the
repository workflow token. With neither project variable configured, board sync is explicitly
skipped. Partial project configuration fails the job.

Rerun a failed merge-completion job to repair partial progress. Labels and closure are
idempotent, and `autobot-done` tasks remain eligible for project repair. A project API failure
leaves the task completed, posts an issue warning with the run link, and fails the job rather
than claiming the board was updated. Fix the project field/option, token permissions, or SSO,
then rerun. Other API errors also fail the job. Copilot acceptance is serialized with merge
completion and skips closed PRs and already-done issues to avoid moving them back to review.
All issue-triggered phases, PR completion jobs, and event-driven project sync share a
per-issue lifecycle lock. PR jobs resolve the branch's issue number before acquiring it;
issue-triggered polling stays inside the phase's existing lock. Project sync also reads
current terminal state so a queued old label event cannot overwrite **Done**.
The shared concurrency group uses `queue: max` so later events do not replace a
pending merge job. GitHub permits up to 100 pending runs in that group; if the queue is full
or a run is manually canceled, rerun the merge job after the queue clears.

Regression coverage runs in `autobot-tests.yml`. Locally:

```powershell
python -B -m unittest discover -s .github\autobot\tests -v
```

The tests mock GitHub command responses; they do not prove live branch rules, token access,
or project configuration. Before releasing, use a sandbox repository to approve/merge a task
PR and verify the label, completed closure, and **Done** project stage, then rerun the job.
Also check that approval without merge and an unmerged PR closure leave the task in review.

## Invariants enforced by workflows

- INV-1: One trigger label per phase.
- INV-2: Implement phase requires `autobot-task`.
- INV-3: Trigger actor must have write access.
- INV-4: Per-issue concurrency group prevents race duplicates.
- INV-5: Deterministic per-issue branch reuse for PR updates.
- INV-6: Missing `CODEX_API_KEY` blocks before agent run for phases configured with provider `codex`.
- INV-7: Plan phase issue creation is idempotent for both main feature and task issues.
- INV-8: `autobot-ready-to-implement` closes the original issue only after successful rollover to main feature + tasks.
- INV-9: Main feature issue always carries the design summary and task links.
- INV-10: Issue text is treated as untrusted input and side effects are workflow-owned.
- INV-11: Copilot mode completion is accepted only for PRs that include the expected assignee and run token.
- INV-12: No automatic fallback from `github-copilot` to `codex` is allowed.
- INV-13: No automatic phase skipping across human gates.
- INV-14: Rejected implementation PRs do not auto-restart; human relabel is required.
- INV-15: Rework input includes PR requested-changes/review comments plus task issue comments.
- INV-16: Spec artifact upload uses SAS-only access with separate write/read SAS; write SAS must never be exposed in comments/logs.
- INV-17: Merge completion applies only to the correlated task after a same-repository implementation PR merges into the default branch.
- INV-18: Completion retries preserve non-phase labels and repair closure/project state without completing parent features.

Copilot handoff details:

- For `spec`, `plan`, and `implement`, the issue-triggered workflow creates and publishes a deterministic handoff branch, then creates or updates a draft handoff PR and exits quickly.
- Handoff branches:
  - `spec`/`implement`: `autobot/<issue>-<slug>`
  - `plan`: `autobot-plan/<issue>-<slug>`
- Handoff PRs include a run token and initial phase artifact commit under `.autobot/output/` so a PR is openable immediately.
- Spec/plan/implement handoff auto-posts a PR instruction comment that mentions `@copilot` (or `AUTOBOT_COPILOT_TRIGGER_HANDLE`) with phase-specific required actions.
- When `AUTOBOT_COPILOT_TRIGGER_TOKEN` is set, those instruction comments are posted with the token owner identity (recommended when Copilot ignores bot-authored mentions).
- Completion is event-driven: `autobot-copilot-complete.yml` runs on PR updates/comments, validates assignee + issue reference + run token, and applies workflow-owned side effects.
- Spec completion requires a design document at `docs/<issue-number>-*/design.md` in the handoff PR branch.
- With `AUTOBOT_COPILOT_STRICT_ARTIFACT=false`, spec/implement can be accepted without manually editing the artifact when required branch changes are present. Set strict mode to `true` to require explicit `status=completed` artifacts.
- Issue-triggered Copilot phase runs can wait briefly and self-evaluate completion for spec/plan/implement; this reduces dependence on follow-up PR event approvals.

Project sync mapping handled by router and phase scripts:

- `autobot-ready-for-spec` -> `Ready for spec`
- `autobot-creating-specification` -> `Creating specification`
- `autobot-review-specification` -> `Review specification`
- `autobot-ready-to-implement` / `autobot-task` -> `Ready to implement`
- `autobot-implementing` -> `Implementing`
- `autobot-in-review` -> `In review`
- `autobot-blocked` -> `Blocked`
- `autobot-done` -> `Done` (synced directly by merge completion)
- issue closed -> `Done`

## Release contract for reusable workflows

Tags are published only after sandbox validation of AC-1 through AC-27 in
`docs/autobot-provider-agnostic-workflow-contract/design.md`. Consumer repositories should pin either:

- a major compatibility tag (`@v1`), or
- an exact release tag (`@v1.2.0`).

If workflows fail with `reference to workflow should be either a valid branch, tag, or commit`,
the referenced tag does not exist yet in the baseline repository. Verify available tags with:

```bash
gh release list --repo AutoplanAS/AutoplanArchitectureSetup
gh api repos/AutoplanAS/AutoplanArchitectureSetup/tags --jq '.[].name'
```

When no release tag is available yet, pin temporarily to `@main` until a release tag is published.

## Troubleshooting

| Symptom | Root cause | Fix |
|---|---|---|
| `reference to workflow should be either a valid branch, tag, or commit` | The ref in `uses: AutoplanAS/AutoplanArchitectureSetup/...@<ref>` does not exist | Pin to an existing tag/commit/branch (`@v1` once published, or temporary `@main`) |
| `Could not resolve to a ProjectV2 with the number <n> (organization.projectV2)` | Project access is missing for the workflow token, or owner/number is wrong | Verify `AUTOBOT_PROJECT_OWNER` + `AUTOBOT_PROJECT_NUMBER`; grant `AUTOBOT_PROJECT_TOKEN` with project scope for private org projects |
| Spec design is generated but Azure Blob links/files are missing | Spec artifact publishing is disabled or incomplete (`AUTOBOT_SPEC_ARTIFACTS_ENABLED=false`, missing storage settings, or missing SAS secrets) | Set `AUTOBOT_SPEC_ARTIFACTS_ENABLED=true`, verify `AUTOBOT_SPEC_ARTIFACTS_STORAGE_ACCOUNT` + `AUTOBOT_SPEC_ARTIFACTS_CONTAINER`, and provide `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS` + `AUTOBOT_SPEC_ARTIFACTS_READ_SAS` |
| `bash: .autobot-baseline/machinist/scripts/install-autoplan-skills.sh: No such file or directory` | Baseline repository/ref resolved to a repo that does not contain Machinist scripts | Use `AUTOBOT_BASELINE_REPOSITORY=AutoplanAS/AutoplanArchitectureSetup` and a valid `AUTOBOT_BASELINE_REF` (for example `v1` or `main`) |
| `autobot-router` run shows `action_required` with no jobs after Copilot bot activity | Repository Actions policy requires approval for bot-originated workflow runs | Autobot now self-evaluates completion from issue-triggered spec/plan/implement runs for a bounded window. If the phase still does not complete after that window, approve the run in Actions UI or add a maintainer PR comment to trigger a trusted `issue_comment` run |

## Sandbox validation checklist

Run the acceptance checks AC-1 through AC-27 from
`docs/autobot-provider-agnostic-workflow-contract/design.md` in a sandbox repository before cutting
a reusable workflow tag.
