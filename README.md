# Autoplan architecture setup

This repository is the **base skill and automation setup** for new Autoplan projects.

It defines a layered model:

| Layer | Purpose | Scope |
|---|---|---|
| Blueprint (generic) | Engineering workflow skills (`architecture`, `design`, `plan`, `task-to-pr`, etc.) | Any software project |
| Autoplan backend skills | Autoplan integration standards (.NET Functions, auth, persistence, IaC, pipelines for Azure DevOps and GitHub, testing, docs) | Backend/integration work |
| Autoplan webapp skills | VehiclePortal-style split web architecture (React + Node API + Azure SQL + hybrid deploy) | Web/full-stack app work |
| Autobot GitHub Actions pipeline (optional) | Label-triggered reusable workflow pipeline with human gates between spec, planning, and implementation | Teams wanting middle-ground automation without self-hosted workers |
| Machinist factory (optional) | Queueing/orchestration layer for issue-to-PR automation using the same skill stacks | Automation at scale |

For full reference, see [DOCUMENTATION.md](DOCUMENTATION.md).

## Getting started for a new project

1. Copy the skill packages into the new repository:
   - `autoplan-backend-skills`
   - `autoplan-webapp-skills`
   - `owain-blueprint-system-development-skills` (optional local snapshot/reference)
   - `machinist` (optional automation factory package)
2. Install the generic Blueprint skills:
   ```powershell
   npx skills add owainlewis/blueprint
   ```
3. Install Autoplan backend skills:
   ```powershell
   .\autoplan-backend-skills\scripts\Install-Skills.ps1 -Target Copilot
   ```
4. Install Autoplan webapp skills:
   ```powershell
   .\autoplan-webapp-skills\scripts\Install-Skills.ps1
   ```
5. Start a new Copilot session and verify skills are available:
   ```text
   /skills list
   ```
6. (Optional) Configure Machinist automation from the included package:
   - `machinist/config.toml.example`
   - `machinist/worker.toml.example`
   - `machinist/workflows/issue-to-pr/README.md`
7. (Optional) Configure the Autobot label-triggered GitHub Actions pipeline:
   - `.github/autobot/README.md`
   - `.github/workflows/autobot.yml`
   - `.github/workflows/autobot-setup.yml`
   - canonical workflow contract: `docs/autobot-provider-agnostic-workflow-contract/design.md`
   - set provider routing variables:
     - `AUTOBOT_SPEC_PROVIDER`, `AUTOBOT_PLAN_PROVIDER`, `AUTOBOT_IMPLEMENT_PROVIDER`
     - optional values: `codex` or `github-copilot` (default is `codex`)
     - `AUTOBOT_COPILOT_ASSIGNEE` is required if any phase uses `github-copilot`
     - optional `AUTOBOT_COPILOT_TRIGGER_HANDLE` (default `@copilot`) for Copilot handoff PR instruction mentions
     - optional `AUTOBOT_COPILOT_TRIGGER_TOKEN` secret to post Copilot handoff `@copilot` instruction comments as a human identity
     - optional `AUTOBOT_COPILOT_SPEC_AUTOCOMPLETE_WAIT_MINUTES` (default `20`, max `180`) for in-run spec completion polling
     - optional `AUTOBOT_COPILOT_PLAN_AUTOCOMPLETE_WAIT_MINUTES` (default `20`, max `180`) for in-run plan completion polling
     - optional `AUTOBOT_COPILOT_IMPLEMENT_AUTOCOMPLETE_WAIT_MINUTES` (default `20`, max `180`) for in-run implement completion polling
     - optional `AUTOBOT_COPILOT_TIMEOUT_MINUTES` (default `90`)
     - timeout value is a handoff SLA hint in Copilot comments; short in-run completion polling is controlled by the phase-specific autocomplete variables
     - optional `AUTOBOT_COPILOT_STRICT_ARTIFACT` (`false` default; set `true` to require explicit completed phase artifacts in Copilot mode)
   - set optional spec artifact mirror variables:
     - `AUTOBOT_SPEC_ARTIFACTS_ENABLED` (`true`/`false`, default `false`; when `false`, no Azure Blob upload is attempted)
     - `AUTOBOT_SPEC_ARTIFACTS_STORAGE_ACCOUNT` (required when enabled)
     - `AUTOBOT_SPEC_ARTIFACTS_CONTAINER` (required when enabled)
     - optional `AUTOBOT_SPEC_ARTIFACTS_PREFIX` (default `autobot-spec`)
     - optional `AUTOBOT_SPEC_ARTIFACTS_ENDPOINT_SUFFIX` (default `blob.core.windows.net`)
   - set optional spec artifact mirror secrets (required when enabled):
     - `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS`
     - `AUTOBOT_SPEC_ARTIFACTS_READ_SAS`
   - set repository variables for project sync:
     - `AUTOBOT_PROJECT_OWNER` (example: `AutoplanAS`)
     - `AUTOBOT_PROJECT_NUMBER` (example: `8`)
     - optional `AUTOBOT_PROJECT_STATUS_FIELD` (default: `Status`)
   - grant `AUTOBOT_PROJECT_TOKEN` if project-scope write is required
   - run lifecycle with explicit human gates:
     - `autobot-ready-for-spec` -> `autobot-creating-specification` -> `autobot-review-specification`
     - human approval applies `autobot-ready-to-implement`
     - planning creates/reuses a new main feature + task issues, then closes the original specification issue as superseded
     - human starts each task by labeling it `autobot-implementing`
     - implementation completion sets `autobot-in-review`

## Which skillsets to use

| Project type | Recommended setup |
|---|---|
| Integration/API only | Blueprint + Autoplan backend skills |
| Web frontend with backend API | Blueprint + Autoplan backend skills + Autoplan webapp skills |
| Generic non-Autoplan project | Blueprint only |

## Automation factory (optional)

If the project needs automated issue-to-PR execution, use the Machinist package in
[`machinist/`](machinist/README.md). It routes requests into backend/webapp/generic workflows
without changing the underlying skill standards.

If the project needs a lighter model with human gates between phases, use the Autobot reusable
workflow package in [`.github/autobot/`](.github/autobot/README.md).

## Maintenance

After updating these skill folders:

1. Pull latest changes in the project.
2. Re-run both install scripts.
3. Start a new Copilot session.

Notes:

- `autoplan-backend-skills` installer uses **Auto** mode by default (prefers symlink, falls back to copy).
- `autoplan-webapp-skills` installer also uses **Auto** mode by default (prefers symlink, falls back to copy).

## Package docs

- Backend package: [autoplan-backend-skills/README.md](autoplan-backend-skills/README.md)
- Webapp package: [autoplan-webapp-skills/README.md](autoplan-webapp-skills/README.md)
- Generic Blueprint package: [owain-blueprint-system-development-skills/README.md](owain-blueprint-system-development-skills/README.md)
- Machinist package: [machinist/README.md](machinist/README.md)
