# Autobot multi-provider execution (Codex and GitHub Copilot)

> **Status:** Proposed for review

## 1. Requirements: what and why

Autobot workflows are currently tied to Codex CLI and `CODEX_API_KEY`. That works for Codex-first
repositories, but it blocks teams that want execution inside the GitHub-native Copilot flow. Those
teams still want the same phase model, labels, project-stage sync, and deterministic workflow-owned
state transitions.

The required outcome is a provider model where each phase can be configured to run with either Codex
or GitHub Copilot, without changing the user-facing Autobot labels or phase semantics.

Required capabilities:

- Per-phase provider selection for spec, planning, and implementation.
- A stable phase-output contract so workflow side effects remain deterministic.
- GitHub Copilot support using issue assignment and PR-based completion.
- Clear timeout/blocked behavior with no automatic provider fallback.
- Backward compatibility: existing Codex repositories keep current behavior by default.

Constraints:

- Existing labels and phase names stay the source of truth.
- Project #8 stage sync remains aligned to labels and phase outcomes.
- Secrets and permissions must stay least-privilege.

Out of scope:

- Supporting providers beyond Codex and GitHub Copilot in this change.
- Replacing the Autobot phase model or adding merge automation.
- Refactoring prompt content quality beyond provider integration needs.

## 2. User experience

A repository admin configures provider variables once:

- `AUTOBOT_SPEC_PROVIDER`
- `AUTOBOT_PLAN_PROVIDER`
- `AUTOBOT_IMPLEMENT_PROVIDER`

Allowed values are `codex` and `github-copilot`. If unset, value defaults to `codex`.

When a trigger label is applied, the user experience remains phase-based:

1. A run starts and comments that Autobot accepted the phase.
2. If the provider is Codex, behavior matches today.
3. If the provider is GitHub Copilot, Autobot assigns the issue to a configured Copilot assignee,
   posts a run token comment, and waits for a matching Copilot PR until timeout.
4. On completion, Autobot applies the same label transitions and project-stage updates as today.

Failure and recovery:

- If provider configuration is invalid, Autobot comments the exact invalid value and applies
  `autobot-blocked`.
- If Copilot is not assignable, does not create a matching PR, or produces an invalid output
  contract before timeout, Autobot comments the reason and applies `autobot-blocked`.
- There is no automatic fallback to Codex. Recovery is explicit: fix config/content and retrigger.

## 3. Technical design and choices

### Provider contract

**Decision:** add provider adapters behind one shared phase contract.  
Each phase script calls `run_phase_provider <phase>` and receives a normalized result payload:

- `status` (`completed` or `blocked`)
- `summary`
- phase-specific structured output used by workflow-owned side effects

This keeps existing deterministic workflow control while allowing provider-specific execution logic.
The main cost is adapter complexity and extra validation logic.

### Configuration and defaults

**Decision:** use repository variables, not workflow-file edits, for provider selection.

- `AUTOBOT_SPEC_PROVIDER`, `AUTOBOT_PLAN_PROVIDER`, `AUTOBOT_IMPLEMENT_PROVIDER`
- `AUTOBOT_COPILOT_ASSIGNEE` (required when any phase uses `github-copilot`)
- `AUTOBOT_COPILOT_TIMEOUT_MINUTES` (default 90, max 360)

Secrets:

- Codex phases require `CODEX_API_KEY`.
- Copilot phases do not require `CODEX_API_KEY`, but still require GitHub token permissions for
  issue assignment, PR read/write, labels, and project sync.

This choice favors operational control and backward compatibility. The tradeoff is more repo-level
configuration.

### GitHub Copilot adapter

**Decision:** for Copilot mode, use assignment plus PR correlation token.

Flow:

1. Generate run token `autobot-<phase>-<issue>-<run-id>`.
2. Comment token and required output contract on the issue.
3. Assign issue to `AUTOBOT_COPILOT_ASSIGNEE`.
4. Poll for a PR that:
   - references the issue,
   - is authored by the Copilot assignee account, and
   - includes the run token in body or comment.
5. Validate phase output from the PR and complete normal side effects.

For planning phase, Copilot PR must include machine-readable task payload in a defined file path
(`.autobot/output/plan.json`) so Autobot can create issues deterministically.

This fits the requirement to keep work inside GitHub framework. The cost is higher latency and one
extra PR artifact for planning.

### Invariants

- **INV-1:** Provider selection is explicit per phase (`codex` or `github-copilot`) and defaults to
  `codex` when unset.
- **INV-2:** Side effects (labels, project stage, issue creation, PR metadata updates) remain
  workflow-owned for both providers.
- **INV-3:** Copilot mode accepts completion only from PRs correlated by run token and expected
  author identity.
- **INV-4:** No automatic provider fallback is allowed. Provider failure leads to
  `autobot-blocked`.
- **INV-5:** Planning-phase task creation remains idempotent regardless of provider.

### Failure, security, and operations

Trust boundaries:

- Issue body and Copilot/Codex text outputs remain untrusted input.
- Existing secret-content guard is reused before posting generated content.

Operational limits:

- Copilot polling uses bounded timeout and interval (for example 2-minute polling).
- On timeout, phase exits blocked with reason and run URL.
- Concurrency keys remain per issue to prevent duplicate transitions.

Rejected alternative:

- Automatic fallback to Codex after Copilot timeout was rejected. It hides provider failure and can
  produce unexpected spend and behavior changes.

## 4. Acceptance and proof

| ID | Done when | How to check |
|---|---|---|
| AC-1 | With no provider variables set, all phases still run with Codex behavior | Run existing label-flow sandbox checks and compare with baseline outputs |
| AC-2 | Setting `AUTOBOT_*_PROVIDER=github-copilot` for one phase routes only that phase to Copilot adapter | Trigger one phase and verify assignment + token comment + Copilot polling logs |
| AC-3 | Copilot phase completion is accepted only with matching run token and expected author | Submit a PR without token or from another author and verify phase stays blocked |
| AC-4 | Copilot timeout or assignment failure applies `autobot-blocked` with actionable reason | Force timeout/invalid assignee and verify label + comment behavior |
| AC-5 | No automatic fallback occurs when Copilot fails | Configure Copilot mode with missing assignee and verify Codex is not invoked |
| AC-6 | Planning phase in Copilot mode creates deterministic `autobot-task` issues from `.autobot/output/plan.json` and remains idempotent | Trigger plan twice with same source output and verify no duplicate task issues |
| AC-7 | Project stage sync remains correct across new provider modes | Run phase transitions in Project #8 and verify stage mappings still match labels |
| AC-8 | Documentation clearly describes provider variables, secrets, and recovery steps | Manual doc review against implemented workflow behavior |

## 5. Open questions

1. **Copilot assignee identity per organization.** Recommended: keep `AUTOBOT_COPILOT_ASSIGNEE`
   mandatory and repository-configurable, with no hardcoded account name. **Non-blocking** because
   implementation can enforce required configuration.
2. **Plan artifact retention policy for Copilot PRs.** Recommended: keep planning PR open until task
   issues are created, then close with a standard comment to reduce board noise. **Non-blocking**.

