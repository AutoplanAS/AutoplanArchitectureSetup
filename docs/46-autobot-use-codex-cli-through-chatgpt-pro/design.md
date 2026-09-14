# Autobot: Codex CLI with ChatGPT Pro authentication

> **Status:** Proposed for review
> Feature: #46. Evidence checked 2026-09-14. This document proposes behavior; it does not enable account access or provision a runner.

## 1. Requirements: what and why

Autobot operators want to use their existing ChatGPT Pro access for spec, plan, and implementation work, avoiding separate API usage where possible. Successful runs should retain the label-triggered workflow and human review gates, without Copilot assignment or manual completion artifacts.

Autobot already uses Codex CLI. The change is an optional authentication mode, not a new provider. Preserve API authentication by default and existing GitHub Copilot routing. Do not silently switch billing modes when credentials or quota fail.

Official documentation describes saved ChatGPT authentication for non-interactive execution, but excludes public/open-source repositories from this account-auth CI pattern. Consequently this proposal supports private, trusted repositories only. It does not promise unlimited usage or permanent unattended login. [Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)

Out of scope: subscription purchase, shared account access, custom OAuth refresh services, migrating Copilot, automatic merge, and ephemeral-runner credential write-back. Runner provisioning remains an operator prerequisite.

## 2. User experience

An administrator prepares one dedicated Linux self-hosted runner for one private repository, installs a reviewed Codex release, and signs in with the intended Pro account using a separate automation login session. The administrator enables `AUTOBOT_CODEX_AUTH_MODE=chatgpt`. Existing per-phase provider variables remain `codex` for phases using this account.

After setup, a maintainer applies the usual label. Spec produces a design PR, plan creates task issues, and implementation produces a task PR through the existing workflow-owned completion path. No browser login is requested inside a job. The job reports the selected authentication mode without identifying the account or printing credentials.

Missing login, wrong authentication type, unsupported configuration, exhausted allowance, or a CLI failure produces a blocked result with a safe recovery instruction. The operator restores login or waits for account allowance, then reapplies the phase label. No automatic purchase or API fallback occurs. A runner that is offline leaves the Actions job queued; GitHub's runner status is the diagnostic, since no phase script can report until a runner starts.

Rollback is setting the mode to `api` and providing the existing `CODEX_API_KEY`. API phases continue on GitHub-hosted runners. Copilot phases ignore the Codex auth mode.

## 3. Technical design and choices

### Verified baseline and configuration

The three reusable phase workflows under `.github/workflows/autobot-{spec,plan,implement}.yml` currently use `ubuntu-latest`, install an unpinned CLI, and pass `CODEX_API_KEY`. The corresponding `run_*_phase.sh` scripts require that key for `codex`. `workflow_common.sh` routes providers and runs Codex. Its current fallback can rerun with sandboxing disabled. Phase scripts own GitHub mutations after reading output JSON and `RESULT`/`SUMMARY` lines. No root `ARCHITECTURE.md` exists.

Add optional reusable input `codex_auth_mode` with exact values `api|chatgpt`, default `api`, passed from `AUTOBOT_CODEX_AUTH_MODE` in both the repository router and `.github/autobot/examples/autobot.yml`. Forward it as `AUTOBOT_CODEX_AUTH_MODE` to all phase scripts. Keep provider names and artifact schemas unchanged. Centralize auth validation in `workflow_common.sh`; replace all three unconditional Codex key checks with mode-aware checks. Update `.github/autobot/README.md` and `DOCUMENTATION.md`, including the existing INV-6 description: API mode requires the key; ChatGPT mode requires a valid managed session.

For a Codex phase in ChatGPT mode, select `[self-hosted, linux, x64, autobot-chatgpt]`; otherwise retain `ubuntu-latest`. The administrator must assign this label to exactly one runner registered only to the adopting private repository. Multiple repositories require separately established sessions and runners, never copied refresh credentials. Before dispatching work to that runner, a GitHub-hosted preflight job verifies target repository equals the caller repository, its authoritative visibility is private, and the authenticated event is `issues/labeled` for the expected phase label and issue number. Check write access for the actual `github.actor`, require the supplied actor to match it, and reject mismatches; caller inputs alone are not authorization evidence. For implement, also verify the current issue has `autobot-task`. Unknown visibility, failed permission lookup, and invalid mode block through the existing issue reporting path. These additional checks apply only to ChatGPT mode and run before checkout or access to persistent credentials. The phase's existing actor validation remains defense in depth. The trusted baseline workflow revision owns this preflight; do not load its authorization logic from the target issue branch.

### Authentication and execution

Use the runner service account's default Codex home, outside checkout, with directory mode 0700 and `auth.json` mode 0600. This also preserves the current skill installer's home conventions. The operator configures file-backed credentials (`cli_auth_credentials_store="file"`) and `forced_login_method="chatgpt"`; commands enforce these settings explicitly so repository configuration cannot select API auth. `codex login status` and managed-session shape validation run without emitting their raw output. Reject missing or malformed files, symlinks, unsafe ownership/permissions, non-ChatGPT auth, and absent refresh tokens. The CLI remains responsible for validating and refreshing credentials online. The enforced authentication setting is documented in the [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

Codex can reuse stored login, and login status exposes the authentication method. Browser login or `codex login --device-auth` is performed by the operator during setup/recovery, never by the phase. [Authentication](https://learn.chatgpt.com/docs/auth)

Preserve the refreshed file in place after every outcome. Never reseed on every job or log out during cleanup. A nonblocking OS file lock outside checkout covers validation and the entire Codex process tree, including reviewers. If held, return blocked with a retry instruction. The operator uses the same lock for reseeding. This protects the session across phases without replacing existing per-issue concurrency groups. Account-auth guidance requires one serialized session stream and preserving renewed credentials; it recommends a persistent runner as the simplest automated option. [Account authentication in CI/CD](https://learn.chatgpt.com/docs/auth/ci-cd-auth)

For ChatGPT mode use a single supported `codex exec` invocation, stdin prompt, explicit workspace-write sandbox, and no interactive approvals. Disable the shared runner's legacy prompt and sandbox-bypass retries in this mode. Missing flags or sandbox bootstrap failure block; they never escalate execution. Bound execution to 90 minutes with a 30-second termination grace, kill remaining child processes before releasing the lock, and accept success only when exit status is zero, the result marker is completed, and the current phase JSON passes validation. Delete stale phase output before invocation. Failure overwrites any apparent success with a phase-specific blocked artifact and matching markers. Preserve existing workflow-owned side effects only after validation.

Install one exact tested CLI version on the dedicated runner; record it in the operator setup documentation at implementation time and verify the same version in preflight on the runner. Do not run the existing global unpinned npm installation in ChatGPT mode. Release verification must cover the required sandbox flags, login status, managed-session format, and independent reviewer support. API mode retains its existing installation behavior.

### Trust boundary and operations

**INV-11:** ChatGPT mode cannot select API credentials or an alternative provider, even when both secrets exist. Remove API key variables from its child environment and enforce OpenAI/ChatGPT configuration for every invocation.

**INV-12:** Persistent account credentials are used only on the dedicated private runner, with one session writer at a time. Never expose this runner to public/fork PR jobs or general build workloads. Execute only the maintainer-authorized Autobot label flow. Issue text remains untrusted data, not shell input or runtime configuration. Repository code and dependencies executed by implementation tasks remain a trust requirement; a filesystem sandbox is not a complete boundary against malicious code running as the same OS user.

**INV-13:** Credentials and raw CLI diagnostics never enter commits, phase JSON, comments, job logs, caches, or uploaded artifacts. Keep raw logs in a private temporary directory outside checkout and delete them on exit; publish only allowlisted error categories and final contract messages. The credential file stays outside checkout and is never included by broad artifact uploads. Extend the outbound guard to scan phase JSON, PR titles, comments, and every staged file before any publication. Privately collect token values from the auth file before and after execution, and reject exact matches plus recognizable credential formats without logging matched values or prefixes. Reject symlinks or unsupported file content that the guard cannot safely inspect; emit only a fixed blocked reason. This prevents accidental disclosure, not deliberately encoded exfiltration by malicious trusted code. Install skills in copy mode from the trusted baseline, replacing managed copies on each run, so retained skills never point into a deleted checkout. Clean the checkout and temporary execution files after each run; retain the auth home and installed skill copies. A workflow-owned always-run cleanup step runs after completion mutations or failure reporting; the execution wrapper also handles termination signals. Cancellation must terminate the process tree before cleanup. Abrupt host loss can require operator cleanup and renewed login.

No extra GitHub secret-write permission or auth-file secret is introduced. Provisioning, account access, machine patching, and revocation remain administrator responsibilities. This deliberately trades hosted-runner convenience for a simpler credential lifecycle. Enable spec first in a private sandbox repository, prove all three phases, then opt in other repositories. Existing callers require no migration.

## 4. Acceptance and proof

Implementation must add isolated shell/Python fixtures under `.github/autobot/tests/`, using stub Codex and GitHub commands without live credentials. Run `python -m unittest discover -s .github/autobot/tests -p 'test_*.py'` plus `bash -n` on changed scripts. Fixtures must cover these observable conditions:

| ID | Done when | How to check |
|---|---|---|
| AC-1 | Default API and Copilot routing remain compatible | Exercise all three phases with unset mode, API mode, and Copilot; assert current outputs and key requirements. |
| AC-2 | ChatGPT configuration propagates and uses the private runner only after authorization | Parse router, example, and reusable workflows; test invalid mode, public/unknown visibility, target mismatch, forged actor/issue/label, non-label events, denied actor, and private authorized cases; assert no self-hosted execution for denied cases. |
| AC-3 | INV-11 holds | With both credential types present, assert child environment/config uses only ChatGPT; invalid/missing/API-only auth blocks before model invocation. |
| AC-4 | INV-12 holds and renewal survives | Hold the OS lock from another process; assert blocked and no CLI call. Fake CLI updates auth, exits successfully or fails; next invocation sees updated content. Confirm operator reseeding uses the lock. |
| AC-5 | Failure cannot produce success side effects | Simulate quota/auth failures, unsupported flags, sandbox errors, nonzero exit with completed markers, malformed/missing/stale JSON, and timeout with child processes. Assert blocked contract, no fallback, child termination, and no completion mutations. |
| AC-6 | INV-13 holds | Inject token canaries before/after refresh into diagnostics, JSON, PR titles, comments, and staged files; assert publication is blocked with no canary or token prefix in captured output. Check cleanup on success/failure/termination and skill availability after checkout deletion. |
| AC-7 | Real account operation meets the feature outcome | On the intended Pro account and a private test repository, complete spec, plan, and implement without API credentials or in-job login. Record CLI version, run links, auth mode, and human interventions, never tokens. Verify a later job reuses the maintained session and test revocation recovery. |

## 5. Open questions

No blocking design decision remains for implementing this opt-in capability. Deployment prerequisites are unverified: the intended repository's visibility, availability of a dedicated runner, the account's Codex entitlement/allowance, and a compatible pinned CLI version. Recommended default is disabled until AC-7 passes; public repositories must retain API or Copilot mode. If the feature must run on a public repository or exclusively on ephemeral runners, this proposal requires a new design decision before that deployment.

Independent architecture review verdict: **Approve**. The reviewer checked the proposal against the router, reusable workflow, all three phase scripts, shared execution helper, and skill installer; no material findings or open design questions remained. Live CLI, account, session renewal, and runner behavior remain unverified and are required by AC-7 before rollout.
