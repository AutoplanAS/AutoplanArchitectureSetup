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
| `.github/workflows/autobot-project-sync.yml` | Reusable | Add issue to project and set stage/status field |
| `.github/workflows/autobot-setup.yml` | Dispatch | Create or refresh required labels |
| `.github/workflows/autobot.yml` | Router | Label + pull-request event router for this repository |

## Label contract

| Label | Trigger | Outcome |
|---|---|---|
| `autobot-ready-for-spec` | Spec phase starts | Codex: direct design PR. Copilot: handoff PR + `autobot-creating-specification` |
| `autobot-ready-to-implement` | Plan phase starts | Codex: create task issues. Copilot: handoff PR, then create task issues on completion |
| `autobot-in-review` | Implement phase starts | Codex: direct task PR updates. Copilot: handoff PR, then completion comment/stage sync on PR updates |
| `autobot-creating-specification` | No | Design waiting for human review |
| `autobot-review-specification` | No | Human review/rework gate before planning |
| `autobot-task` | No | Marks issue as implementation task |
| `autobot-blocked` | No | Phase needs human decision |

When spec completes, the issue moves to `autobot-creating-specification` and Autobot posts both the
design PR and design file link. Human approval is the PR merge: review and merge that PR, then add
`autobot-ready-to-implement` to the same feature issue to start plan generation.

## Required secrets

- `CODEX_API_KEY` (required only for phases configured with provider `codex`)
- `BASELINE_REPO_TOKEN` (optional; required only if this baseline repository is private)
- `AUTOBOT_PROJECT_TOKEN` (required for organization-owned project boards such as `AutoplanAS#8`)

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
- `AUTOBOT_COPILOT_TIMEOUT_MINUTES` (optional handoff SLA hint in comments, default `90`, max `360`)
- `AUTOBOT_COPILOT_STRICT_ARTIFACT` (`true`/`false`, default `false`; strict mode requires explicit completed phase artifact payloads before acceptance)

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

- For `spec`, `plan`, and `implement`, the issue-triggered workflow creates and publishes a deterministic handoff branch, then creates or updates a draft handoff PR and exits quickly.
- Handoff branches:
  - `spec`/`implement`: `autobot/<issue>-<slug>`
  - `plan`: `autobot-plan/<issue>-<slug>`
- Handoff PRs include a run token and initial phase artifact commit under `.autobot/output/` so a PR is openable immediately.
- Completion is event-driven: `autobot-copilot-complete.yml` runs on PR updates/comments, validates author + issue reference + run token, and applies workflow-owned side effects.
- With `AUTOBOT_COPILOT_STRICT_ARTIFACT=false`, spec/implement can be accepted without manually editing the artifact when required branch changes are present. Set strict mode to `true` to require explicit `status=completed` artifacts.

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
| `bash: .autobot-baseline/machinist/scripts/install-autoplan-skills.sh: No such file or directory` | Baseline repository/ref resolved to a repo that does not contain Machinist scripts | Use `AUTOBOT_BASELINE_REPOSITORY=AutoplanAS/AutoplanArchitectureSetup` and a valid `AUTOBOT_BASELINE_REF` (for example `v1` or `main`) |

## Sandbox validation checklist

Run the acceptance checks AC-1 through AC-14 from `docs/autobot-pipeline/design.md` in a sandbox
repository before cutting a reusable workflow tag.
