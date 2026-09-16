# Autoplan architecture setup documentation

This document is the full reference for using this repository as the baseline for new projects.

---

## 1. Purpose

This repository standardizes how Autoplan projects bootstrap AI agent skills.

The target outcome for a new project is:

1. The team has a **generic engineering workflow baseline** (Blueprint).
2. The team has **Autoplan backend standards** installed.
3. Web/full-stack teams also have **Autoplan webapp standards** installed.
4. Teams that need scaled automation can enable **Machinist issue-to-PR orchestration**.
5. Teams that need phased automation with human gates can enable the **Autobot GitHub Actions pipeline**.

---

## 2. Skillset model

Autoplan uses layered capabilities that solve different problems.

| Layer | Main responsibility | Typical trigger examples |
|---|---|---|
| Blueprint (generic) | Decide, plan, deliver, test, review with consistent engineering workflow | "design this", "plan this feature", "review this PR", "test this change" |
| Autoplan backend skills | Integration/backend implementation standards | "new integration", "OAuth2 client credentials", "Azure Table Storage", "Bicep", "azure-pipelines.yml", ".github/workflows/deploy.yml", "SQL MERGE alignment" |
| Autoplan webapp skills | Lightweight webapp architecture and delivery standards | "React frontend", "Node API handler", "JWT + RBAC", "Vercel + App Service deploy" |
| Machinist factory (optional) | Queueing and orchestration for issue-to-PR execution using the same skill stacks | "process requested issues", "run delivery queue", "label-driven implementation" |

### 2.1 Autoplan has two domain skillsets

Within Autoplan-specific skills, there are two main domain bundles:

1. **Backend skillset**: `autoplan-backend-skills`
2. **Web development skillset**: `autoplan-webapp-skills`

Blueprint is intentionally separate and generic for any project type.

---

## 3. Repository layout

| Path | Role |
|---|---|
| `autoplan-backend-skills/` | Installable backend standards package |
| `autoplan-webapp-skills/` | Installable webapp standards package |
| `owain-blueprint-system-development-skills/` | Local snapshot/reference of Blueprint source |
| `machinist/` | Optional automation factory package (commands, prompts, wrappers, config templates) |
| `.github/autobot/` | Optional reusable GitHub Actions package for label-driven phased execution |
| `README.md` | Quick-start operator guide |
| `DOCUMENTATION.md` | Full architecture and operations reference |

---

## 4. Getting started in a new repository

Use this when creating a new project that should follow the same approach.

### 4.1 Copy baseline folders

Copy these folders from this repository into the new repository root:

1. `autoplan-backend-skills`
2. `autoplan-webapp-skills`
3. `owain-blueprint-system-development-skills` (optional local reference snapshot)
4. `machinist` (optional automation factory package)

### 4.2 Install generic Blueprint skills

Preferred method:

```powershell
npx skills add owainlewis/blueprint
```

Why preferred:

- Pulls the upstream maintained generic skillset.
- Keeps generic workflow skills independent from Autoplan package releases.

### 4.3 Install Autoplan backend skills

From the project root:

```powershell
.\autoplan-backend-skills\scripts\Install-Skills.ps1 -Target Copilot
```

Important behavior:

- `-Mode Auto` is default.
- Auto mode attempts **symlink** first, then falls back to **copy** if symlink is unavailable.
- Supports multi-agent installation (`Copilot`, `Claude`, `Codex`, `Gemini`) via `-Target`.

Examples:

```powershell
.\autoplan-backend-skills\scripts\Install-Skills.ps1 -Target Copilot,Claude
.\autoplan-backend-skills\scripts\Install-Skills.ps1 -Mode Copy -Force
```

### 4.4 Install Autoplan webapp skills

From the project root:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1
```

Optional:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Target Claude
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Mode Symlink
```

### 4.5 Verify installation

Start a new Copilot session and check:

```text
/skills list
```

Expected:

- Generic Blueprint skills are visible.
- Autoplan backend skills are visible.
- Autoplan webapp skills are visible.

### 4.6 Optional: configure Machinist factory automation

If the project needs issue-to-PR automation, use:

- `machinist/README.md`
- `machinist/config.toml.example`
- `machinist/worker.toml.example`
- `machinist/workflows/issue-to-pr/README.md`

Minimal setup:

1. Install both Autoplan skill packages on the worker machine.
2. Use repo-local `machinist/*.toml` templates, or copy them to `~/.machinist/` and also copy
   `machinist/prompts/` there (or switch prompt paths to absolute paths).
3. Run direct mode first (`machinist run`) before enabling managed triggers.

### 4.7 Optional: configure Autobot phased workflow automation

Use:

- `.github/autobot/README.md`
- `.github/autobot/examples/autobot.yml`
- `.github/workflows/autobot-setup.yml`
- `docs/autobot-provider-agnostic-workflow-contract/design.md` (canonical workflow contract)

Minimal setup:

1. Grant `CODEX_API_KEY` secret only if one or more phases use provider `codex`.
   - Obtain the key value from your Codex provider API portal (for example, OpenAI), then store it as
     an organization Actions secret named `CODEX_API_KEY`.
   - Grant that org secret to each adopting repository; do not commit keys to the repo.
2. Add `.github/workflows/autobot.yml` in the target repository (use the example file).
   - Use a valid reusable-workflow ref (`@v1`, specific release tag, commit SHA, or temporary `@main`).
   - If Actions reports `reference to workflow should be either a valid branch, tag, or commit`, the chosen ref is not published in `AutoplanAS/AutoplanArchitectureSetup`.
3. Run `autobot-setup` to provision `autobot-*` labels.
4. Configure provider routing variables:
   - `AUTOBOT_SPEC_PROVIDER`, `AUTOBOT_PLAN_PROVIDER`, `AUTOBOT_IMPLEMENT_PROVIDER`
   - allowed values: `codex` or `github-copilot` (defaults to `codex`)
   - `AUTOBOT_COPILOT_ASSIGNEE` required when any phase uses `github-copilot`
   - optional `AUTOBOT_COPILOT_TRIGGER_HANDLE` (default `@copilot`) for Copilot handoff PR instruction mentions
   - optional `AUTOBOT_COPILOT_TRIGGER_TOKEN` secret to post Copilot handoff instruction comments as a human identity
   - optional `AUTOBOT_COPILOT_SPEC_AUTOCOMPLETE_WAIT_MINUTES` (default `20`, max `180`) to keep the issue-triggered spec run open and self-evaluate completion when design appears
   - optional `AUTOBOT_COPILOT_PLAN_AUTOCOMPLETE_WAIT_MINUTES` (default `20`, max `180`) to keep the issue-triggered plan run open and self-evaluate completion when plan artifact output appears
   - optional `AUTOBOT_COPILOT_IMPLEMENT_AUTOCOMPLETE_WAIT_MINUTES` (default `20`, max `180`) to keep the issue-triggered implement run open and self-evaluate completion when implementation output appears
   - optional `AUTOBOT_COPILOT_TIMEOUT_MINUTES` (handoff SLA hint in comments, default `90`, max `360`)
   - optional `AUTOBOT_COPILOT_STRICT_ARTIFACT` (`false` default; set `true` to require explicit completed phase artifacts in Copilot mode)
   - optional `AUTOBOT_BASELINE_REPOSITORY` (defaults to `AutoplanAS/AutoplanArchitectureSetup`)
   - optional `AUTOBOT_BASELINE_REF` (defaults to `v1`; set when you need a different branch/tag/commit)
5. Configure project sync variables in the target repository:
   - `AUTOBOT_PROJECT_OWNER` (for Project #8 this is `AutoplanAS`)
   - `AUTOBOT_PROJECT_NUMBER` (for Project #8 this is `8`)
   - optional `AUTOBOT_PROJECT_STATUS_FIELD` (defaults to `Status`)
6. Grant `AUTOBOT_PROJECT_TOKEN` when project-scope write is required by the org project permissions model.
   - If Actions reports `Could not resolve to a ProjectV2 with the number <n> (organization.projectV2)`, verify `AUTOBOT_PROJECT_OWNER` / `AUTOBOT_PROJECT_NUMBER` and ensure `AUTOBOT_PROJECT_TOKEN` can access that org project.
7. Drive phases by labels with explicit human gates:
   - spec trigger: `autobot-ready-for-spec`
   - review gate label: `autobot-review-specification`
   - plan trigger: `autobot-ready-to-implement`
   - implementation trigger: `autobot-implementing`
   - implementation review state: `autobot-in-review` (not a trigger)
8. Planning rollover behavior:
   - planning runs on the original approved-spec issue,
   - creates or reuses a new main feature issue,
   - creates/reuses linked `autobot-task` issues,
   - then closes the original specification issue as superseded.
9. Spec artifact mirror behavior (optional, SAS-only):
   - configure variables: `AUTOBOT_SPEC_ARTIFACTS_ENABLED`, `AUTOBOT_SPEC_ARTIFACTS_STORAGE_ACCOUNT`, `AUTOBOT_SPEC_ARTIFACTS_CONTAINER`, optional `AUTOBOT_SPEC_ARTIFACTS_PREFIX`, optional `AUTOBOT_SPEC_ARTIFACTS_ENDPOINT_SUFFIX`
   - configure secrets: `AUTOBOT_SPEC_ARTIFACTS_WRITE_SAS`, `AUTOBOT_SPEC_ARTIFACTS_READ_SAS`
   - in this increment, only spec artifacts are mirrored (`design.md`, `design.html`) plus a branch-scoped `latest.json` pointer.
   - If Actions reports `bash: .autobot-baseline/machinist/scripts/install-autoplan-skills.sh: No such file or directory`, ensure `AUTOBOT_BASELINE_REPOSITORY` points to `AutoplanAS/AutoplanArchitectureSetup` (or another baseline containing Machinist scripts) and `AUTOBOT_BASELINE_REF` exists there.

---

## 5. Choosing the right setup by project type

| Project type | Install |
|---|---|
| Non-Autoplan or generic internal project | Blueprint only |
| Autoplan integration/backend service | Blueprint + backend |
| Autoplan web portal with API/backend | Blueprint + backend + webapp |

### 5.1 Typical sequence for backend-heavy projects

1. Use Blueprint to define and plan the change (`design`, `plan`).
2. Use `autoplan-integration-scaffold` for project shape.
3. Use `autoplan-integration-auth`, `autoplan-external-api-client`, `autoplan-data-persistence`, `autoplan-sql-model-alignment`.
4. Use `autoplan-azure-deploy` and either `autoplan-devops-pipeline` (Azure DevOps) or `autoplan-github-pipeline` (GitHub Actions).
5. Use `autoplan-integration-testing`.
6. Use `autoplan-integration-docs` for README + DOCUMENTATION quality.

### 5.2 Typical sequence for web/full-stack projects

1. Use Blueprint to define architecture and plan.
2. Use `autoplan-webapp-architecture` first.
3. Use `autoplan-webapp-frontend-react` and `autoplan-webapp-api-node`.
4. Use `autoplan-webapp-auth-data`.
5. Use `autoplan-webapp-testing-quality`.
6. Use `autoplan-webapp-deployment-hybrid`.

---

## 6. Operations and lifecycle

### 6.1 Updating skills

When this baseline repo is updated:

1. Pull latest changes in each consumer repo.
2. Re-run install scripts:
   - `.\autoplan-backend-skills\scripts\Install-Skills.ps1`
   - `.\autoplan-webapp-skills\scripts\Install-Skills.ps1`
3. Start a new agent session.

### 6.2 Symlink vs copy

| Mode | Effect | Tradeoff |
|---|---|---|
| Symlink | Skills update automatically when source repo changes | Requires symlink permission |
| Copy | Works everywhere | Must re-run install scripts after updates |

### 6.3 Uninstalling

Backend package:

```powershell
.\autoplan-backend-skills\scripts\Uninstall-Skills.ps1 -Target Copilot
```

Webapp package:

```powershell
.\autoplan-webapp-skills\scripts\Uninstall-Skills.ps1
```

### 6.4 Factory operations with Machinist (optional)

Use the wrapper scripts for direct single-request execution:

- PowerShell: `.\machinist\workflows\issue-to-pr\run-local.ps1 -Prompt "<request>"`
- Bash: `./machinist/workflows/issue-to-pr/run-local.sh --prompt "<request>"`

Use managed mode only after direct mode is validated for your repo and CI rules.

### 6.5 Autobot operations (optional)

Autobot is intentionally label-driven and phase-gated, with the same behavior for Codex and
GitHub Copilot providers:

1. A feature issue labeled `autobot-ready-for-spec` starts specification work.
2. Autobot moves the issue to `autobot-creating-specification` while producing/updating the design PR.
3. When ready, Autobot sets `autobot-review-specification` and posts design links.
4. Human review gate:
   - for rework, comment and relabel `autobot-ready-for-spec`;
   - for approval, label `autobot-ready-to-implement`.
5. Planning runs on the original approved-spec issue and creates/reuses a main feature issue and linked `autobot-task` issues.
6. After successful rollover, Autobot closes the original specification issue as superseded by the main feature.
7. Human starts task implementation by labeling the task issue `autobot-implementing`.
8. Autobot implements to a deterministic branch/PR and, on success, sets `autobot-in-review`.
9. If PR changes are requested, implementation does not auto-restart; a human must reapply `autobot-implementing`.

If a phase cannot proceed, workflows remove the trigger label and add `autobot-blocked` with a
comment containing the reason and run link.

Provider routing behavior:

1. Each phase resolves its provider independently (`codex` or `github-copilot`).
2. Unset provider variables default to `codex`.
3. `github-copilot` mode is event-driven:
   - issue-trigger workflows publish a deterministic handoff branch and create/update a draft handoff PR;
   - completion is evaluated by `autobot-copilot-complete` on PR events and can also be self-invoked from bounded issue-trigger polling.
4. Handoff branches:
   - `spec`/`implement`: `autobot/<issue>-<slug>`
   - `plan`: `autobot-plan/<issue>-<slug>`
5. Copilot completion requires the PR to reference the issue, include the run token, and include the
   configured assignee on the PR.
6. `AUTOBOT_COPILOT_STRICT_ARTIFACT=false` (default) allows spec/implement completion without
   manual artifact edits when expected branch changes exist; `true` requires explicit completed
   artifacts.
7. Spec completion requires a design file at `docs/<issue-number>-*/design.md` in the handoff PR.
8. Spec/plan/implement handoffs auto-post phase-specific PR instruction comments mentioning `@copilot` (or `AUTOBOT_COPILOT_TRIGGER_HANDLE`).
9. Issue-triggered Copilot runs can wait briefly and self-evaluate completion for spec/plan/implement to reduce dependence on follow-up PR event approvals.
10. There is no automatic fallback to Codex when Copilot mode fails.
11. External spec artifact publishing is optional and non-blocking; canonical repository links remain source of truth.
12. External spec artifact publishing uses SAS-only Azure Blob access with separate write/read SAS tokens.
13. Rejected implementation PR feedback is included in rework context, but rework run start still requires explicit relabel.

Project stage sync mapping:

1. `autobot-ready-for-spec` -> `Ready for spec`
2. `autobot-creating-specification` -> `Creating specification`
3. `autobot-review-specification` -> `Review specification`
4. `autobot-ready-to-implement` and new `autobot-task` issues -> `Ready to implement`
5. `autobot-implementing` -> `Implementing`
6. `autobot-in-review` -> `In review`
7. `autobot-blocked` -> `Blocked`
8. issue closed -> `Done`

---

## 7. Governance notes

1. Keep generic workflow concerns in Blueprint.
2. Keep Autoplan-specific delivery standards in Autoplan skillsets.
3. Avoid duplicating generic guidance from Blueprint into Autoplan skills unless Autoplan needs an explicit convention override.
4. Treat `SKILL.md` as concise entry instructions; keep deep details in `references/`.

---

## 8. Verified against repository state

The following was verified directly in this repository:

1. `autoplan-backend-skills` exists with install/uninstall scripts and backend Autoplan skill folders.
2. `autoplan-webapp-skills` exists with install/uninstall scripts and six webapp skill folders.
3. `owain-blueprint-system-development-skills` exists and contains the generic Blueprint skill catalog under `skills/`.
4. `machinist` exists with command prompts, config templates, skill bootstrap scripts, and issue-to-PR workflow wrappers.

Package references:

- `autoplan-backend-skills/README.md`
- `autoplan-webapp-skills/README.md`
- `owain-blueprint-system-development-skills/README.md`
- `machinist/README.md`

---

## 9. Assumptions

1. Copilot environment supports `/skills list` for skill visibility checks.
2. Teams have PowerShell available to run installation scripts.
3. New projects can include these folders as part of their baseline repository structure.
4. Teams enabling Machinist can host worker/config files in either repo-local or user-level Machinist paths.

---

## 10. Decisions log

| Date | Decision | Reason |
|---|---|---|
| 2026-09-11 | Use this repository as baseline documentation source for project bootstrapping | Gives one canonical onboarding flow across projects |
| 2026-09-11 | Keep Blueprint treated as generic, independent layer | Prevents Autoplan project-specific coupling into generic engineering workflow guidance |
| 2026-09-11 | Document Autoplan backend and webapp as the two primary Autoplan domain skillsets | Matches how teams split backend integration work and web delivery work |
| 2026-09-11 | Keep backend and webapp install commands explicit in root docs | Reduces setup variance and onboarding drift |
| 2026-09-11 | Add Machinist as optional orchestration layer packaged in-repo | Enables automation/factory operation without coupling orchestration logic into skill content |
