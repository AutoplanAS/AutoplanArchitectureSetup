# Autobot provider-agnostic workflow contract alignment

> **Status:** Proposed for review

## 1. Requirements: what and why

Autobot already supports both Codex and GitHub Copilot execution paths, but the current workflow state machine does not fully match the intended human-gated delivery process. In particular, implementation currently starts from `autobot-in-review`, which conflates "start coding" and "human PR review", and the handoff between approved specification and implementation-ready tasks is underspecified for cross-provider consistency.

The required outcome is one provider-agnostic phase contract where Codex and Copilot runs must follow the same issue lifecycle and project-stage mapping:

- `autobot-ready-for-spec` starts specification work.
- `autobot-creating-specification` means Autobot is producing the design artifact.
- `autobot-review-specification` is the explicit human gate for design acceptance or rework.
- `autobot-ready-to-implement` starts planning from approved design.
- Planned task issues are created in **Ready to implement** and are explicitly marked as Autobot tasks.
- `autobot-implementing` starts implementation for one approved task.
- `autobot-in-review` means implementation is complete and awaiting human PR review.
- Closing an approved issue moves it to **Done**.

Constraints:

- No automatic phase skipping, regardless of provider.
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
4. Human review happens in **Review specification**:
   - If changes are needed, the reviewer comments, moves back to **Ready for spec**, and reapplies `autobot-ready-for-spec`.
   - If approved, the reviewer applies `autobot-ready-to-implement`.
5. Autobot planning (`plan` skill) creates task issues from approved design. Each task is created in **Ready to implement** with task marker labels, and the feature issue remains a parent/coordinator.
6. A human approves a task for coding by adding `autobot-implementing`.
7. Autobot implementation (`task-to-pr` skill) runs for that task, moves issue to **Implementing** during active work, then sets `autobot-in-review` when the PR is ready.
8. Human reviews the PR:
   - If changes are needed, reviewer comments and the task returns to implementation flow (`autobot-implementing`).
   - If approved and completed, issue is closed and stage becomes **Done**.

Failure outcomes:

- Missing configuration, invalid provider, or artifact contract failure applies `autobot-blocked` with a single actionable comment.
- Retries always require explicit human re-labelling.

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
- Plan script ensures all created sub-issues receive `autobot-task` and land in **Ready to implement**.
- Copilot completion script applies the same terminal labels/stages as Codex scripts for each phase.

### Invariants

- **INV-1:** Provider selection must never change label transition semantics.
- **INV-2:** Only one trigger label starts each phase.
- **INV-3:** `autobot-in-review` is terminal for implementation phase, never a phase trigger.
- **INV-4:** Implementation can start only for issues marked as Autobot tasks.
- **INV-5:** Human approval gates between spec, plan, and implementation are mandatory and explicit.
- **INV-6:** Issue/project stage mapping is derived from current labels and close state, not provider-specific outputs.
- **INV-7:** Alias labels (`autoboot*`) are normalized to canonical labels before phase logic executes.

### Security and operations

Issue and PR text remain untrusted input; scripts continue to own all state transitions and secret-guard checks before posting generated content. Concurrency remains per issue to prevent duplicate runs. Timeouts and provider misconfiguration continue to end in `autobot-blocked` with run URL for operator recovery.

## 4. Acceptance and proof

| ID | Done when | How to check |
|---|---|---|
| AC-1 | Label `autobot-ready-for-spec` starts spec run and sets `autobot-creating-specification` while work is in progress | Label a sandbox feature issue and inspect labels plus project stage |
| AC-2 | Completed spec output moves issue to `autobot-review-specification` and **Review specification** | Complete a spec run (Codex and Copilot modes) and verify resulting labels/stage |
| AC-3 | Reviewer rework loop works by commenting and reapplying `autobot-ready-for-spec` | Simulate review feedback and confirm retrigger behavior |
| AC-4 | Label `autobot-ready-to-implement` creates task issues with `autobot-task` in **Ready to implement** | Trigger plan and verify issue labels/stage for all created tasks |
| AC-5 | Label `autobot-implementing` starts implementation and sets stage **Implementing** | Label a task issue and verify run start state |
| AC-6 | Successful implementation changes label/state to `autobot-in-review` and stage **In review** | Complete implementation and verify issue label/stage |
| AC-7 | `autobot-in-review` does not trigger new implementation runs | Apply `autobot-in-review` directly and verify no implementation workflow dispatch |
| AC-8 | Closing approved issue moves stage to **Done** | Close a reviewed task issue and verify stage update |
| AC-9 | Codex and Copilot produce identical label/state transitions for same phase events | Run one end-to-end sandbox flow per provider and diff resulting issue timelines |
| AC-10 | `autoboot*` alias labels are normalized to canonical labels without duplicate runs | Apply alias labels in sandbox and verify canonical label replacement plus single run |

## 5. Open questions

1. **Alias retirement timeline.** Recommended: keep `autoboot*` normalization for two release tags, then remove once usage telemetry shows near-zero alias events. **Non-blocking**.
2. **Task marker consolidation.** Recommended: keep `autobot-task` as authoritative and optionally add `autoboot` as migration-only companion label, then deprecate companion label later. **Non-blocking**.
