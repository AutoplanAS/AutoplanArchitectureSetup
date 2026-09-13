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
| `.github/workflows/autobot-project-sync.yml` | Reusable | Add issue to project and set stage/status field |
| `.github/workflows/autobot-setup.yml` | Dispatch | Create or refresh required labels |
| `.github/workflows/autobot.yml` | Router | Label event router for this repository |

## Label contract

| Label | Trigger | Outcome |
|---|---|---|
| `autobot-ready-for-spec` | Spec phase starts | On success: design PR + `autobot-creating-specification` |
| `autobot-ready-to-implement` | Plan phase starts | On success: task issues labelled `autobot-task` |
| `autobot-in-review` | Implement phase starts | On success: one task PR |
| `autobot-creating-specification` | No | Design waiting for human review |
| `autobot-review-specification` | No | Human review/rework gate before planning |
| `autobot-task` | No | Marks issue as implementation task |
| `autobot-blocked` | No | Phase needs human decision |

## Required secrets

- `CODEX_API_KEY` (required only for phases configured with provider `codex`)
- `BASELINE_REPO_TOKEN` (optional; required only if this baseline repository is private)
- `AUTOBOT_PROJECT_TOKEN` (optional; required when project sync needs project-scope token)

When Codex is used, `CODEX_API_KEY` should be managed as an org-level secret and granted to each
adopting repository.

Project sync uses repository variables:

- `AUTOBOT_PROJECT_OWNER` (for example `AutoplanAS`)
- `AUTOBOT_PROJECT_NUMBER` (for example `8`)
- `AUTOBOT_PROJECT_STATUS_FIELD` (optional, defaults to `Status`)

Provider routing uses repository variables:

- `AUTOBOT_SPEC_PROVIDER` (`codex` or `github-copilot`, default `codex`)
- `AUTOBOT_PLAN_PROVIDER` (`codex` or `github-copilot`, default `codex`)
- `AUTOBOT_IMPLEMENT_PROVIDER` (`codex` or `github-copilot`, default `codex`)
- `AUTOBOT_COPILOT_ASSIGNEE` (required when any phase uses `github-copilot`; must be a real assignable GitHub login in the target repository)
- `AUTOBOT_COPILOT_TIMEOUT_MINUTES` (optional, default `90`, max `360`)

## Adopting in another repository

1. Add labels using this repository's setup workflow:
   - Run `autobot-setup` in this repo and set `target_repository=owner/repo`.
2. Add caller workflow:
   - Copy `.github/autobot/examples/autobot.yml` into target repo as `.github/workflows/autobot.yml`.
3. Grant secrets in target repository:
   - `CODEX_API_KEY` (only needed for phases that use provider `codex`)
   - `BASELINE_REPO_TOKEN` only if needed.
   - `AUTOBOT_PROJECT_TOKEN` when project scope permissions are required.
4. Configure provider routing variables for your preferred execution model.

## Invariants enforced by workflows

- INV-1: One trigger label per phase.
- INV-2: Implement phase requires `autobot-task`.
- INV-3: Trigger actor must have write access.
- INV-4: Per-issue concurrency group prevents race duplicates.
- INV-5: Deterministic per-issue branch reuse for PR updates.
- INV-6: Missing `CODEX_API_KEY` blocks before agent run for phases configured with provider `codex`.
- INV-7: Plan phase issue creation is idempotent.
- INV-8: Issue text is treated as untrusted input and side effects are workflow-owned.
- INV-9: Copilot mode completion is accepted only for PRs that match expected author and run token.
- INV-10: No automatic fallback from `github-copilot` to `codex` is allowed.

Copilot handoff details:

- For `spec` and `implement` phases, the workflow creates and publishes the deterministic branch (`autobot/<issue>-<slug>`) before waiting for a correlated Copilot PR.
- Copilot-mode completion still requires the PR to reference the issue, include the run token, and contain the required phase artifact file.

Project sync mapping handled by router and phase scripts:

- `autobot-ready-for-spec` -> `Ready for spec`
- `autobot-creating-specification` -> `Creating specification`
- `autobot-review-specification` -> `Review specification`
- `autobot-ready-to-implement` / `autobot-task` -> `Ready to implement`
- `autobot-in-review` -> `In review`
- `autobot-blocked` -> `Blocked`
- issue closed -> `Done`

## Release contract for reusable workflows

Tags are published only after sandbox validation of AC-1 through AC-14 in
`docs/autobot-pipeline/design.md`. Consumer repositories should pin either:

- a major compatibility tag (`@v1`), or
- an exact release tag (`@v1.2.0`).

## Sandbox validation checklist

Run the acceptance checks AC-1 through AC-14 from `docs/autobot-pipeline/design.md` in a sandbox
repository before cutting a reusable workflow tag.
