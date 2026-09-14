# Cursor as an Autobot provider

> **Status:** Proposed for review

## 1. Requirements: what and why

Issue #32 asks for Cursor alongside Codex and GitHub Copilot so repository operators have another provider choice. Support `cursor` independently for specification, planning, and implementation in the existing GitHub Actions pipeline. Preserve default selection, human design approval, task dependencies, output schemas, and workflow-owned GitHub operations. Success means each phase can complete through Cursor without Codex credentials or a Copilot assignee.

This proposal adds the Cursor CLI on the existing Linux runner. Cursor cloud-agent handoffs, automatic failover, model selection controls, desktop setup, Windows installers, and redesigning existing providers are out of scope. No root ARCHITECTURE.md exists; the implementation references below establish the current behavior.

## 2. User experience

An operator grants the repository an Actions secret named `CURSOR_API_KEY`, updates the caller workflow to a release containing this change, and sets any of `AUTOBOT_SPEC_PROVIDER`, `AUTOBOT_PLAN_PROVIDER`, or `AUTOBOT_IMPLEMENT_PROVIDER` to `cursor`. Other phases retain their configured provider; unset or empty values still select `codex`. Case normalization remains supported, including `Cursor`; surrounding whitespace remains invalid.

The operator applies the existing phase label. Cursor runs within the Actions job. A successful specification produces the existing design PR, planning creates the existing task issues from the merged design, and implementation produces the existing task PR. Copilot completion events ignore Cursor phases.

Unknown provider values or missing Cursor credentials block with an actionable configuration message. Installation, authentication, CLI capability, timeout, and output-contract failures also block without publishing partial work. The operator corrects the cause and reapplies the phase label. There is no provider fallback or automatic retry. An already-running job keeps its resolved provider; configuration changes affect later runs.

## 3. Technical design and choices

### Routing and workflow wiring

Today `.github/autobot/scripts/workflow_common.sh` validates two providers and sends every non-Codex dispatch to Copilot. Replace that implicit fallback with explicit cases for `codex`, `cursor`, and `github-copilot`; add `run_cursor_prompt` with phase, prompt, log, and output paths. Add provider-specific credential preflight in all three `run_*_phase.sh` scripts after actor authorization and before starting an agent or preparing a handoff.

In `run_spec_phase.sh`, the design existence check and commit/push block currently require `provider == codex`. Extend that local-execution branch to Cursor. Plan and implementation already continue locally after the Copilot early exit; verify their success and failure paths explicitly. Keep Copilot correlation and completion exclusive to `github-copilot`.

Declare optional `CURSOR_API_KEY` in the three reusable phase workflows, forward it from `.github/workflows/autobot.yml` and `.github/autobot/examples/autobot.yml`, and expose it only to the selected Cursor phase process. Update provider descriptions, including completion-workflow descriptions where applicable. Select installation using the same case-normalized provider as dispatch: Codex installs only for Codex, Cursor only for Cursor, neither CLI for Copilot. Retain Node for the existing skill bootstrap.

Use Cursor's official HTTPS installer, downloaded with failure checking before execution, add its documented binary directory to PATH, and record `agent --version`. CLI or skill installation failure must reach the existing blocked reporting path rather than terminate before reporting; capture setup failure and pass a fixed diagnostic to phase preflight. Use the rolling installer initially, matching existing CLI provisioning, with a required capability check and a real-run release gate. This avoids inventing an unsupported version pin but accepts upstream compatibility risk. [Cursor GitHub Actions documentation](https://cursor.com/docs/cli/github-actions).

### Execution, skills, and result contract

Run the installed Cursor `agent` from the target checkout with `--print --force --trust --output-format text`, passing the generated prompt as one quoted argument without `eval`. API authentication uses `CURSOR_API_KEY` in the environment, never an argument. The workflow explicitly trusts the checked-out workspace for headless operation. Check required options before invocation; an incompatible CLI blocks without trying alternate flags. Cursor documents noninteractive file editing through these flags. [Headless CLI](https://cursor.com/docs/cli/headless), [CLI parameters](https://cursor.com/docs/cli/reference/parameters).

Extend `machinist/scripts/install-autoplan-skills.sh` with target `cursor` mapped to `$HOME/.cursor/skills`. Install the existing Autoplan packages for that target when selected, and ensure the existing Blueprint bootstrap installs readable design, architecture-review, plan, task-to-pr, review, and test skills in a Cursor-discoverable location. Do not duplicate skill contents or weaken independent-review requirements. Missing required skills block. Verify subagent review in the release smoke; unavailable independent review must report blocked rather than silently self-review. [Cursor skills documentation](https://cursor.com/docs/skills).

**INV-1:** Cursor completes only when its process exits zero, stdout contains exactly one completed RESULT and one nonempty SUMMARY, and a newly generated phase JSON validates against the existing prompt schema with completed status and empty blocked_reason. Remove the previous phase JSON before invocation. Capture stderr separately so diagnostics cannot satisfy the stdout contract. Require a nonempty design file for spec; validate plan task field types and dependency references before issue creation (a nonempty task array, nonempty string titles and bodies, unique trimmed titles, and string dependencies naming only earlier tasks); validate required spec/implement text fields. Invalid, missing, or contradictory output produces a fresh blocked JSON through `write_provider_blocked_output` and a normalized blocked log, regardless of partial files. For a zero-exit, schema-valid blocked response whose RESULT agrees with JSON, preserve its nonempty blocked_reason after both the existing secret guard and an exact nonempty `CURSOR_API_KEY` value check pass and use that reason as the normalized SUMMARY; if the guard fails, substitute a fixed redacted diagnostic. This preserves the exact missing decision or context without publishing partial work. Validate before downstream GitHub mutations. Retain valid completed JSON and normalize the log for existing consumers.

Bound each Cursor invocation to 90 minutes with a 30-second termination grace, including its child process group. Nonzero exit and timeout always override apparent success. Use fixed public diagnostics by failure category; do not copy arbitrary stderr into comments. No automatic rerun occurs, avoiding duplicated cost and edits. On cancellation, terminate children and permit no publication; platform cancellation may prevent a blocked comment. Discard partial runner work on termination. Existing per-issue concurrency remains unchanged.

### Trust, compatibility, and operations

**INV-2:** Existing prompts continue to treat issue text as data and reserve GitHub publication for the workflow. Pass no GitHub, project, baseline, or Codex tokens into the Cursor child; disable checkout credential persistence for Cursor jobs and supply workflow git authentication only outside that child for fetch/push. Preserve the workflow's actor permission checks, secret guards, and human approval stages. Before publication, check all Cursor-generated public text, the design, and staged file contents for the exact nonempty Cursor credential as well as existing secret patterns; any match blocks using a fixed diagnostic without a secret sample. Keep raw CLI stdout/stderr private to the ephemeral runner and never upload or print them. This detects literal leaks, not encoded secrets. Cursor still receives its own API credential and has shell/file authority via force mode; this is execution in an ephemeral trusted runner, not a security sandbox or a guarantee against malicious repository code.

Do not commit generated runtime files, credentials, or skill installation artifacts. For Cursor implementation staging, exclude `.autobot/`, `.autobot-baseline/`, and only the paths created by this run's skill bootstrap, including generated lockfiles; preserve pre-existing tracked project skill changes. Record bootstrap-created paths before agent execution so the current `git add -A` cannot publish tooling as feature code. Update `.github/autobot/README.md`, root README.md, and DOCUMENTATION.md with selection, secret forwarding, installation assumptions, timeout recovery, and a mixed-provider example. No stored data migration is needed. Roll out opt-in after smoke validation; rollback sets the phase variables to their prior values. No default changes.

## 4. Acceptance and proof

Add isolated tests under `.github/autobot/tests`, runnable with `python -m unittest discover -s .github/autobot/tests -p 'test_*.py'`, using temporary repositories and fake CLI/GitHub commands. These are implementation acceptance tests, not tests executed during this specification phase. Proposed tests must not require real secrets or perform network mutations.

| ID | Done when | How to check |
|---|---|---|
| AC-1 | All phases select Cursor, preserve defaults/case rules, reject unknown values, and never fall through to Copilot | Table-driven routing tests for all phases, empty/unset/mixed-case/invalid values; existing-provider regression scenarios |
| AC-2 | Cursor needs only its own credential and selected setup | Workflow configuration checks for reusable declarations, both callers, normalized install conditions, and preflight tests for missing key and failed install |
| AC-3 | All three Cursor success paths reach the correct existing publisher | Phase integration fixtures: spec stages exact design path and prepares PR; plan consumes merged design and prepares dependent tasks; implementation prepares code PR; fake GitHub calls confirm no Copilot handoff |
| AC-4 | INV-1 rejects every partial or invalid result before publication | Fake agent cases: nonzero with completed output, timeout, missing/duplicate markers, stderr-only markers, stale/missing/malformed JSON, wrong field types, blocked/mismatched statuses, missing design, invalid task dependency; valid blocked reason preserved and secret-like blocked reason redacted, including a sentinel Cursor key without a recognized token prefix |
| AC-5 | INV-2 and cleanup hold | Child environment and git-config probes with sentinel credentials; hostile issue text remains data; failure fixtures assert no publish calls; generated bootstrap paths stay unstaged while tracked project skills remain eligible; exact-key leaks in comments, titles, design, and staged files block; timeout/cancellation fixtures assert child termination |
| AC-6 | Skills and actual Cursor execution work in Actions | Temporary install checks plus opt-in disposable-repository runs for spec, plan, and implement; record CLI version, skill discovery, independent review, valid artifacts, correct PR/task outcomes, and missing-key recovery |

Run `bash -n` on changed shell scripts and validate workflow syntax with actionlint. Mock tests prove routing and contracts; AC-6 is required before declaring the provider operational and is not claimed complete by this design.

## 5. Open questions

None blocking design or planning. The proposal chooses local CLI execution and all three phases from the existing provider interface. Account entitlement, actual CLI skill discovery, and independent subagent execution remain release validation requirements under AC-6, not verified runtime claims.
