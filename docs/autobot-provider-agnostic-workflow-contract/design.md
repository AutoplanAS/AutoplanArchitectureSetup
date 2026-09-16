# Autobot provider-agnostic workflow contract alignment

> **Status:** Proposed for review

## 1. Requirements: what and why

Autobot already supports both Codex and GitHub Copilot execution paths, but the workflow contract still has gaps against the intended human-gated operating model. The biggest gap is around `autobot-ready-to-implement`: today planning creates tasks, but the parent issue lifecycle does not match the desired behavior where the original issue is closed and work continues in a new main feature tracker.

The required outcome is one provider-agnostic phase contract where Codex and Copilot runs must follow the same issue lifecycle and project-stage mapping:

- `autobot-ready-for-spec` starts specification work.
- `autobot-creating-specification` means Autobot is producing the design artifact.
- `autobot-review-specification` is the explicit human gate for design acceptance or rework.
- Spec output must be readable outside branch context by publishing temporary Azure Blob artifacts for the generated design (`.md` and `.html`).
- `autobot-ready-to-implement` starts planning from approved design on the original issue, then closes that original issue as superseded.
- Planning creates a new main feature issue that contains a short human-readable design summary and links to full design and implementation tasks.
- Planned task issues are created in **Ready to implement**, are explicitly marked as Autobot tasks, and are linked from the new main feature issue.
- `autobot-implementing` starts implementation for one approved task.
- `autobot-in-review` means implementation is complete and awaiting human PR review.
- Closing an approved task or main feature issue moves it to **Done**.

Constraints:

- No automatic phase skipping, regardless of provider. In this contract that means Autobot can only do immediate next-step transitions for the active phase, and must never jump across a human gate. Examples: it may move `autobot-ready-for-spec` to `autobot-creating-specification`, but it must not jump directly to `autobot-ready-to-implement`; it may complete `autobot-implementing` to `autobot-in-review`, but it must not auto-close the issue as approved. For rejected implementation PRs, reviewer comments alone must not restart implementation. A human must explicitly reapply `autobot-implementing` on the task issue.
- External artifact scope starts with spec phase only. Only `design.md` and `design.html` are published externally in this increment.
- Any `latest.json` pointer used for external artifact discovery must be namespaced by repository and branch, not globally shared.
- External artifact backend for this increment is Azure Blob Storage only.
- Workflow-owned label and project-stage side effects remain deterministic.
- Existing repositories must have a migration path from typo-prone `autoboot*` labels without breaking active queues.

Out of scope:

- Automatic PR merge or deployment orchestration.
- Multi-branch release flow beyond current main-branch process.
- Adding new AI providers beyond Codex and GitHub Copilot.

## 2. User experience

A human drives lifecycle intent with labels, and Autobot executes only the phase requested by that label.

Main flow:

1. A feature issue is moved to **Ready for spec** and labelled `autobot-ready-for-spec`.
2. Autobot starts specification (`design` skill), removes trigger label, applies `autobot-creating-specification`, and keeps the issue in **Creating specification** while producing or updating the design PR/artifact.
3. When design output is ready, Autobot applies `autobot-review-specification` and removes `autobot-creating-specification`.
   - In the same step, Autobot publishes temporary spec artifacts (`design.md`, `design.html`) to Azure Blob Storage and comments links for branch-independent reading.
4. Human review happens in **Review specification**:
   - If changes are needed, the reviewer comments, moves back to **Ready for spec**, and reapplies `autobot-ready-for-spec`.
   - If approved, the reviewer applies `autobot-ready-to-implement`.
5. Autobot planning (`plan` skill) runs on the original issue and creates:
   - one new main feature issue that becomes the execution parent;
   - a short design summary section for human readability;
   - links to the approved design document and source issue;
   - implementation task issues linked under the main feature.
6. After successful main feature and task creation, Autobot closes the original issue with a "superseded by main feature" comment and links.
7. A human approves a task for coding by adding `autobot-implementing` on a task issue.
8. Autobot implementation (`task-to-pr` skill) runs for that task, moves issue to **Implementing** during active work, then sets `autobot-in-review` when the PR is ready.
9. Human reviews the PR:
   - If changes are needed, reviewer requests changes or comments on the PR, then explicitly reapplies `autobot-implementing` on the task issue to restart implementation.
   - If approved and completed, issue is closed and stage becomes **Done**.
10. The main feature issue stays as the execution summary issue. Humans close it when its linked implementation tasks are done.

Failure outcomes:

- Missing configuration, invalid provider, or artifact contract failure applies `autobot-blocked` with a single actionable comment.
- Retries always require explicit human re-labelling.
- If external spec artifact publishing fails, Autobot keeps the normal repository and PR flow as source of truth, and adds a warning comment with the run link and failure reason.

## 3. Technical design and choices

### Label contract normalization

**Decision:** keep `autobot-*` as canonical labels and add compatibility alias handling for `autoboot*` triggers.  
**Why:** the current repository and workflows already use `autobot-*`; alias support prevents queue loss from typo or legacy usage.  
**Tradeoff:** extra routing and cleanup logic until aliases are retired.

Canonical labels:

- Phase triggers: `autobot-ready-for-spec`, `autobot-ready-to-implement`, `autobot-implementing`
- Phase states: `autobot-creating-specification`, `autobot-review-specification`, `autobot-in-review`, `autobot-blocked`
- Task marker: `autobot-task` (optional companion alias: `autoboot` for discoverability during migration)

### Provider-independent phase engine

**Decision:** enforce identical phase transitions in workflow-owned scripts for both providers.  
**Why:** "regardless of provider" means provider adapters may differ in execution mechanics, but not in lifecycle semantics.  
**Tradeoff:** Copilot completion logic must map to the same transitions as synchronous Codex runs.

Required script and workflow changes:

- Router triggers implement phase on `autobot-implementing` (not `autobot-in-review`).
- Implement script sets stage to **Implementing** at start, then to **In review** only after successful completion.
- Spec script promotes to `autobot-review-specification` once design output is ready; `autobot-creating-specification` remains strictly "work in progress".
- Plan script creates or reuses a deterministic main feature issue keyed to the original issue, writes a short design summary in that issue, creates linked `autobot-task` sub-issues, and places both main feature and tasks in **Ready to implement**.
- Plan script closes the original approved-spec issue after successful main feature and sub-issue creation, with a comment linking to the new main feature issue.
- Copilot completion script applies the same terminal labels/stages as Codex scripts for each phase.
- Implementation rework restart is label-driven only. `pull_request_review` or PR comments by themselves do not restart implementation.
- Every implementation rework run must include reviewer requested-change feedback from the linked PR review/comments plus any new task-issue comments.
- Entering a new phase must remove stale Autobot phase-state labels from earlier phases so the issue has one active phase state.
- Rework cycles must reuse the same deterministic implementation branch and PR for the task issue instead of creating new PR chains.
- Spec completion path mirrors `docs/<issue>-<slug>/design.md` and generated `design.html` to external temporary storage.
- Spec completion writes a `latest.json` pointer under a repo-and-branch-scoped prefix so links are isolated per repository and source branch.

### Spec external artifact mirror on Azure Blob (pilot)

**Decision:** publish only spec artifacts (`design.md` and `design.html`) to temporary Azure Blob Storage in this increment.  
**Why:** it solves the immediate readability problem for reviewers who should not need branch checkout context, while keeping rollout risk low.  
**Tradeoff:** planning and implementation artifacts remain branch-bound until later increments.

Storage contract:

- Prefix: `autobot-spec/<owner>/<repo>/<branch>/issue-<issue-number>/`.
- Immutable run artifacts:
  - `runs/<run-id>/design.md`
  - `runs/<run-id>/design.html`
- Branch-scoped pointer:
  - `latest.json` (same prefix), containing latest run id, source commit SHA, and artifact object paths.

Azure setup contract:

- One Azure Storage account dedicated to Autobot transient review artifacts.
- One private blob container, for example `autobot-spec-artifacts`.
- GitHub Actions uses container-scoped SAS tokens only for this increment.
- SAS model:
  - one write SAS token for workflow upload and pointer updates;
  - one read-only SAS token for reviewer links in issue comments;
  - both tokens are scoped to this dedicated storage account and container.
- SAS tokens should be created from stored access policies so revocation and rotation can be done without changing workflow code.

Publishing behavior:

- Triggered only when spec output reaches completed state and before final review comment is posted.
- Review comment includes both:
  - canonical repository links (design file and PR),
  - external temporary artifact links.
- External artifact upload failure does not roll back phase completion. It emits warning telemetry/comment and keeps repository artifacts as authoritative.

### Required repository variables and secrets for Azure Blob publishing

**Decision:** use explicit repository-level configuration so each repo can route artifacts to its own storage account and branch namespace.  
**Why:** repositories can have different tenants, subscriptions, and retention policies while using the same reusable workflows.  
**Tradeoff:** setup requires more initial configuration and validation checks.

Required configuration:

- Repository variables:
  - `AUTOBOT_SPEC_ARTIFACTS_ENABLED` (`true` or `false`, default `false`).
  - `AUTOBOT_SPEC_ARTIFACTS_STORAGE_ACCOUNT` (Azure Storage account name).
  - `AUTOBOT_SPEC_ARTIFACTS_CONTAINER` (blob container name).
  - `AUTOBOT_SPEC_ARTIFACTS_PREFIX` (optional static prefix root, default `autobot-spec`).
  - `AUTOBOT_SPEC_ARTIFACTS_ENDPOINT_SUFFIX` (optional, default `blob.core.windows.net`, override for sovereign cloud).
- Repository secrets:
  - `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS` (container SAS token with minimum write/list/create permissions for `runs/*` and `latest.json` updates).
  - `AUTOBOT_SPEC_ARTIFACTS_READ_SAS` (container SAS token with read-only permission, used only for reviewer-facing links).

Runtime behavior:

- If `AUTOBOT_SPEC_ARTIFACTS_ENABLED` is `false`, workflows skip external upload and keep repository-only links.
- If enabled and any required Azure setting or SAS secret is missing, spec phase continues but posts a warning and fallback repository links.
- Workflows upload with `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS`, then build reviewer links with `AUTOBOT_SPEC_ARTIFACTS_READ_SAS`.
- Write SAS tokens must never be included in issue comments, logs, PR bodies, or artifact payloads.

### Main feature issue contract

**Decision:** planning rolls work over from original issue to a new main feature issue instead of keeping the original open.  
**Why:** it matches the required operating model and gives one clean implementation tracker with readable summary plus subtask links.  
**Tradeoff:** one additional issue object per feature and stricter idempotency requirements.

Main feature issue content:

- Short summary section generated from approved design intent and lifecycle decisions, formatted for quick human reading.
- Link to full design document (`docs/<issue>-<slug>/design.md`).
- Link back to closed original issue.
- Checklist or ordered list of implementation task issue links.
- Marker metadata for idempotent reruns (for example `Autobot Main Parent: #<original-issue>`).

### Invariants

- **INV-1:** Provider selection must never change label transition semantics.
- **INV-2:** Only one trigger label starts each phase.
- **INV-3:** `autobot-in-review` is terminal for implementation phase, never a phase trigger.
- **INV-4:** Implementation can start only for issues marked as Autobot tasks.
- **INV-5:** Human approval gates between spec, plan, and implementation are mandatory and explicit.
- **INV-6:** Issue/project stage mapping is derived from current labels and close state, not provider-specific outputs.
- **INV-7:** Alias labels (`autoboot*`) are normalized to canonical labels before phase logic executes.
- **INV-8:** `autobot-ready-to-implement` must close the original issue only after a main feature issue and all planned tasks are successfully materialized.
- **INV-9:** The main feature issue must always contain links to every planned implementation task issue.
- **INV-10:** "No automatic phase skipping" means transitions are limited to one phase step and can never cross a human review gate.
- **INV-11:** Rejected implementation PRs restart only when a human reapplies `autobot-implementing` on the task issue.
- **INV-12:** Implementation rework runs must ingest PR requested-change feedback and task-issue follow-up comments as mandatory input context.
- **INV-13:** Phase-start actions must remove stale Autobot state labels so only one active phase-state label remains.
- **INV-14:** A task issue keeps one implementation PR and one implementation branch across rework cycles.
- **INV-15:** Only spec phase publishes external artifacts in this increment, and only `design.md` and `design.html` are published.
- **INV-16:** `latest.json` is scoped by `<owner>/<repo>/<branch>/issue-<issue-number>` and must not point across repositories or branches.
- **INV-17:** Spec review comments must include canonical repo links even when external artifact links are present.
- **INV-18:** External artifact publishing failure must not silently pass. It must produce an explicit warning and leave canonical repository artifacts as source of truth.
- **INV-19:** External spec artifacts are stored only in Azure Blob Storage for this increment.
- **INV-20:** Azure Blob publishing must use SAS-only access for this increment, with separate write and read SAS tokens scoped to the artifact container.
- **INV-21:** When artifact publishing is enabled, missing required Azure config or SAS secrets must produce explicit warning output and fallback repository links.
- **INV-22:** Reviewer-facing links must use read-only SAS only, and must never expose the write SAS token.

### Security and operations

Issue and PR text remain untrusted input; scripts continue to own all state transitions and secret-guard checks before posting generated content. Concurrency remains per issue to prevent duplicate runs. Planning reruns must be idempotent for both main feature creation and task creation to avoid duplicate trackers. For implementation rework, one label event may trigger one run only, and repeated human relabels queue deterministic reruns without spawning duplicate PRs. Timeouts and provider misconfiguration continue to end in `autobot-blocked` with run URL for operator recovery.

## 4. Acceptance and proof

| ID | Done when | How to check |
|---|---|---|
| AC-1 | Label `autobot-ready-for-spec` starts spec run and sets `autobot-creating-specification` while work is in progress | Label a sandbox feature issue and inspect labels plus project stage |
| AC-2 | Completed spec output moves issue to `autobot-review-specification` and **Review specification** | Complete a spec run (Codex and Copilot modes) and verify resulting labels/stage |
| AC-3 | Reviewer rework loop works by commenting and reapplying `autobot-ready-for-spec` | Simulate review feedback and confirm retrigger behavior |
| AC-4 | Label `autobot-ready-to-implement` creates a new main feature issue with short design summary, design link, source issue link, and task links | Trigger plan and verify main feature issue body content and links |
| AC-5 | Successful planning closes the original issue only after main feature and tasks exist | Trigger plan and verify close event order in issue timeline |
| AC-6 | Planning creates task issues with `autobot-task` in **Ready to implement** and links them from main feature issue | Verify labels/stage for created tasks and backlink list in main feature |
| AC-7 | Label `autobot-implementing` starts implementation and sets stage **Implementing** | Label a task issue and verify run start state |
| AC-8 | Successful implementation changes label/state to `autobot-in-review` and stage **In review** | Complete implementation and verify issue label/stage |
| AC-9 | `autobot-in-review` does not trigger new implementation runs | Apply `autobot-in-review` directly and verify no implementation workflow dispatch |
| AC-10 | Closing approved task or main feature issue moves stage to **Done** | Close reviewed issue and verify stage update |
| AC-11 | Codex and Copilot produce identical label/state transitions for same phase events | Run one end-to-end sandbox flow per provider and diff resulting issue timelines |
| AC-12 | `autoboot*` alias labels are normalized to canonical labels without duplicate runs | Apply alias labels in sandbox and verify canonical label replacement plus single run |
| AC-13 | No automatic phase skipping occurs: workflows only perform one-step transitions and never cross human gates | Attempt to force skipped transitions by labels/comments and verify workflow blocks or ignores them |
| AC-14 | Rejected implementation PRs restart only from explicit human relabel (`autobot-implementing`) | Submit PR review with requested changes and comment only, verify no run starts; then apply `autobot-implementing` and verify exactly one run starts |
| AC-15 | Rework run context includes reviewer requested-change feedback and task issue follow-up comments | Inspect run input artifact/log and verify review/comment excerpts are present |
| AC-16 | Rework restart cleans stale labels and leaves one active implementation phase-state label | During rerun start, verify label set removes conflicting implementation state labels before work proceeds |
| AC-17 | Rework updates existing task PR/branch rather than creating duplicates | Execute at least two reject/rework cycles and verify same PR number and branch are reused |
| AC-18 | Completed spec publishes external `design.md` and `design.html` artifacts under the expected storage prefix | Run spec in sandbox and verify objects exist at repo+branch+issue scoped paths |
| AC-19 | Branch-scoped `latest.json` points to the newest run artifacts for that repository and branch only | Run two spec completions on same issue/branch and verify pointer update without cross-branch contamination |
| AC-20 | Spec review comment includes both canonical repo links and external artifact links | Inspect resulting issue comment content after spec completion |
| AC-21 | Planning and implementation phases do not publish external artifacts in this increment | Run plan and implement phases and verify no external objects are written |
| AC-22 | External artifact upload failure is visible and non-blocking | Force storage write failure and verify spec still reaches review state with explicit warning comment |
| AC-23 | Azure Blob publishing uses repo+branch+issue scoped paths and stores only `design.md` and `design.html` | Run spec with publishing enabled and verify object names and file types |
| AC-24 | `latest.json` remains branch-scoped and does not cross-reference another branch in same repo | Publish spec from two branches and verify each branch pointer remains isolated |
| AC-25 | SAS-only setup is sufficient for upload and review links without Azure login identity config | Remove Azure login settings, run publish with SAS secrets, and verify upload plus read-link generation succeeds |
| AC-26 | Missing Azure settings or SAS secrets in enabled mode produce fallback behavior without blocking phase completion | Remove one required variable or SAS secret, run spec, and verify warning plus canonical repo links |
| AC-27 | Review comments and logs expose read-only SAS links only, never write SAS tokens | Inspect emitted comments/logs and verify write SAS token material is absent |

## 5. Open questions

1. **Alias retirement timeline.** Recommended: keep `autoboot*` normalization for two release tags, then remove once usage telemetry shows near-zero alias events. **Non-blocking**.
2. **Task marker consolidation.** Recommended: keep `autobot-task` as authoritative and optionally add `autoboot` as migration-only companion label, then deprecate companion label later. **Non-blocking**.
3. **Main feature closure policy.** Recommended: keep human-controlled closure for the main feature issue in v1, and evaluate auto-close only after reliable dependency completeness checks are available. **Non-blocking**.
4. **Rework escalation threshold.** Recommended: after three consecutive rejected implementation cycles on the same task, add `autobot-blocked` with a summary comment that asks for manual triage before another rerun. **Non-blocking**.
5. **External artifact retention window.** Recommended: expire spec mirror artifacts after 60 days, with optional extension for still-open review issues. **Non-blocking**.
6. **SAS rotation cadence.** Recommended: rotate read and write SAS policies every 30 days, with emergency revocation playbook and per-repository token isolation. **Non-blocking**.
