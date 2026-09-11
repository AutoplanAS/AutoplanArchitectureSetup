---
name: autoplan-integration-review
description: "Audit an Autoplan integration against the house standard and produce a prioritised gap report — committed secrets, disabled tests, missing config validation, no resilience, missing IaC or pipeline, monolithic clients, telemetry drift, and unsafe CI deploy gates (Azure DevOps or GitHub Actions). WHEN: \"review this integration\", \"audit this repo\", \"does this follow our standard\", \"conformance check\", \"what's missing in this project\", \"health check this integration\", \"is this repo up to standard\", \"find gaps\", \"tech debt in this integration\", \"onboarding review\", \"pre-handover review\", \"check for committed secrets\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration
---

# Autoplan Integration Review

Audits an integration against the house standard and produces a **prioritised gap report**. Read-only
by default: report first, fix only when asked.

Baseline is EchoesIntegration. Every check below distinguishes a real gap from a deliberate
difference — do not report conformance for its own sake.

## Rules

1. **Report before fixing.** Produce the full report first. A review that silently starts editing hides the gaps it found.
2. **Verify every finding by opening the file.** Never report from a grep hit alone — see [false-positives.md](references/false-positives.md). Several plausible checks here give the wrong answer when run naively.
3. **Severity is about consequence, not effort.** A committed secret is critical even if the fix is one command.
4. **Secrets first.** If a credential is exposed, say so at the top and state that rotation precedes everything else.
5. **Cite file and line** for every finding, so it can be acted on without a second investigation.
6. **No finding without a fix.** Each entry names the concrete change and, where one exists, the skill that describes it.
7. **Route CI checks by platform.** Azure DevOps findings come from `azure-pipelines*.yml` and `Check-Pipeline*`; GitHub findings come from `.github/workflows/*.yml` and `Check-GitHubWorkflow*`.

## Running a review

1. **Identify the function project** — the `.csproj` referencing `Microsoft.Azure.Functions.Worker`. Checks target *that* project, not the whole repo. Sample apps and test projects are excluded.
2. **Run the checks** in [checks.md](references/checks.md), in order. Security first.
3. **Confirm each hit** by opening the file at the cited line.
4. **Write the report** using [report-template.md](references/report-template.md).
5. **Offer the fix order**: security → correctness → conformance.

## Severity

| Level | Meaning | Examples |
|---|---|---|
| ⛔ **Critical** | Credential exposed, or a control that reports success without doing anything | secret committed to git; `PublishTestResults` with no test step |
| ⚠️ **High** | Production failure mode, or no path to safe deployment | no config validation; no resilience handler; no pipeline or IaC |
| **Medium** | Real maintenance or reliability cost | monolithic API client; per-instance token cache; no 401 handling |
| **Low** | Drift from the standard, no immediate impact | App Insights instead of OpenTelemetry; version skew; docs sprawl |

A control that *reports* success without doing the work is Critical, not Medium — it actively
misleads. Easypark's pipeline published test results for a test step that was commented out.

## The check catalogue

Grouped, with full commands and the exact false positives each attracts, in
[checks.md](references/checks.md):

- **Security** — committed secrets, `.gitignore` coverage, `@secure()` params, secrets in logs, anonymous endpoints
- **Correctness** — options validation, resilience, 401 handling, token cache lifetime, cancellation tokens
- **Delivery** — pipeline exists, tests actually execute, IaC present, artifact separation
- **Structure** — central package management, `NuGet.config`, layout, client size
- **Observability** — telemetry standard, what is logged, what must never be

## Reference

- [Check catalogue](references/checks.md)
- [Anti-patterns found in this codebase](references/anti-patterns.md)
- [False positives — read before reporting](references/false-positives.md)
- [Report template](references/report-template.md)
- [Verified baseline per repo](references/current-state.md)

## Related skills

Findings map onto the skill that fixes them:

| Finding area | Skill |
|---|---|
| layout, packages, `Program.cs`, options | `autoplan-integration-scaffold` |
| client shape, resilience, error handling, pagination | `autoplan-external-api-client` |
| tokens, keys, inbound auth, secrets | `autoplan-integration-auth` |
