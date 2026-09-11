# Machinist factory integration

This folder integrates the Machinist automation model into this Autoplan baseline so one worker can
run repeatable issue-to-PR delivery while still using the same skill layers:

1. Blueprint (generic engineering workflow)
2. Autoplan backend skills
3. Autoplan webapp skills

Machinist stays the execution/orchestration layer. Skills stay the implementation and review
guidance layer.

## What is included

| Path | Purpose |
|---|---|
| `config.toml.example` | Machinist command + trigger catalog for Autoplan delivery |
| `worker.toml.example` | Worker executors and repository registration template |
| `prompts/` | Command prompts tuned for Autoplan backend, webapp, and audit flows |
| `scripts/install-autoplan-skills.ps1` | Skill bootstrap for Windows/PowerShell workers |
| `scripts/install-autoplan-skills.sh` | Skill bootstrap for Linux/macOS workers |
| `workflows/issue-to-pr/` | Direct-run wrappers and runbook for issue-to-PR execution |

## Prerequisites

1. Machinist installed and initialized (`machinist init`)
2. `codex` authenticated on the worker host
3. `gh` authenticated on the worker host
4. Git checkout of this repository available on the worker host

## Setup

### 1. Install skills on the worker

PowerShell:

```powershell
.\machinist\scripts\install-autoplan-skills.ps1 -Target Copilot
```

Bash:

```bash
./machinist/scripts/install-autoplan-skills.sh --targets copilot
```

Optional: append `--install-blueprint` (bash) or `-InstallBlueprint` (PowerShell).

### 2. Create worker and command config files

Recommended for this baseline: keep config files inside this repository so `prompt_file` paths work
without edits:

```text
machinist/config.toml.example
machinist/worker.toml.example
```

If you prefer `~/.machinist/*.toml`, also copy `machinist/prompts/` into `~/.machinist/prompts/` or
replace `prompt_file` with absolute paths.

Set at minimum:

- repository slug in `[github.repositories]`
- local checkout path in `[repositories.<name>]`
- command executor definitions matching the installed agent CLIs

### 3. Run one issue directly

```bash
machinist run \
  --config /absolute/path/to/AutoplanArchitectureSetup/machinist/worker.toml.example \
  --machinist-config /absolute/path/to/AutoplanArchitectureSetup/machinist/config.toml.example \
  --command=autoplan-factory-foreman \
  --repo=/absolute/path/to/repo \
  --prompt="Complete https://github.com/owner/repo/issues/123"
```

### 4. Run managed queue mode

```bash
machinist start --config ~/.machinist/config.toml
machinist worker start --config ~/.machinist/worker.toml
```

Then submit work:

```bash
machinist submit \
  --config ~/.machinist/worker.toml \
  --command=autoplan-factory-foreman \
  --repo=autoplan-architecture-setup \
  --prompt="Complete https://github.com/owner/repo/issues/123"
```

## Command catalog

| Command | Prompt file | Primary use |
|---|---|---|
| `autoplan-factory-foreman` | `prompts/autoplan-factory-foreman.md` | Generic issue-to-PR with skillset routing |
| `autoplan-backend-delivery` | `prompts/autoplan-backend-delivery.md` | Backend/integration issues |
| `autoplan-webapp-delivery` | `prompts/autoplan-webapp-delivery.md` | Web/full-stack issues |
| `autoplan-integration-audit` | `prompts/autoplan-integration-audit.md` | Read-only conformance audit |

## Trigger labels (GitHub intake)

| Label | Mapped command |
|---|---|
| `machinist:requested` | `autoplan-factory-foreman` |
| `machinist:requested-backend` | `autoplan-backend-delivery` |
| `machinist:requested-webapp` | `autoplan-webapp-delivery` |

## Operating rules

1. One issue maps to one active delivery branch/PR.
2. The workflow may open/update PRs but does not merge.
3. Human review remains the release gate.
4. Backend/webapp platform specifics are routed to their own skills (`autoplan-devops-pipeline` or
   `autoplan-github-pipeline`).
