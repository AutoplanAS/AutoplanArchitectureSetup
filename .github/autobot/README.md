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
| `autobot-implementing` | Plan phase starts | On success: task issues labelled `autobot-task` |
| `autobot-in-review` | Implement phase starts | On success: one task PR |
| `autobot-creating-specification` | No | Design waiting for human review |
| `autobot-task` | No | Marks issue as implementation task |
| `autobot-blocked` | No | Phase needs human decision |

## Required secrets

- `CODEX_API_KEY` (required by all phase workflows)
- `BASELINE_REPO_TOKEN` (optional; required only if this baseline repository is private)
- `AUTOBOT_PROJECT_TOKEN` (optional; required when project sync needs project-scope token)

`CODEX_API_KEY` is expected to be an org-level secret granted to each adopting repository.

Project sync uses repository variables:

- `AUTOBOT_PROJECT_OWNER` (for example `AutoplanAS`)
- `AUTOBOT_PROJECT_NUMBER` (for example `8`)
- `AUTOBOT_PROJECT_STATUS_FIELD` (optional, defaults to `Status`)

## Adopting in another repository

1. Add labels using this repository's setup workflow:
   - Run `autobot-setup` in this repo and set `target_repository=owner/repo`.
2. Add caller workflow:
   - Copy `.github/autobot/examples/autobot.yml` into target repo as `.github/workflows/autobot.yml`.
3. Grant secrets in target repository:
   - `CODEX_API_KEY`
   - `BASELINE_REPO_TOKEN` only if needed.

## Invariants enforced by workflows

- INV-1: One trigger label per phase.
- INV-2: Implement phase requires `autobot-task`.
- INV-3: Trigger actor must have write access.
- INV-4: Per-issue concurrency group prevents race duplicates.
- INV-5: Deterministic per-issue branch reuse for PR updates.
- INV-6: Missing `CODEX_API_KEY` blocks before agent run.
- INV-7: Plan phase issue creation is idempotent.
- INV-8: Issue text is treated as untrusted input and side effects are workflow-owned.

Project sync mapping handled by router and phase scripts:

- `autobot-ready-for-spec` -> `Ready for spec`
- `autobot-creating-specification` -> `Creating specification`
- `autobot-implementing` / `autobot-task` -> `Implementing`
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
