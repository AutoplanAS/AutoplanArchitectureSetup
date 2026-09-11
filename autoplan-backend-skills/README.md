# Autoplan Copilot Skills

Shared GitHub Copilot **agent skills** encoding the house standards for Autoplan integration
development. One source of truth, used by every integration repo.

These skills were extracted from the existing integrations —
Echoes, Easypark, HubSpot, Drive/SmartCar, OFV and Autoplan API — so they describe what we
actually do, not a generic best-practice list. **EchoesIntegration is the canonical reference
implementation**; where repos disagree, the Echoes pattern wins.

## Why this exists

The standard already existed, it was just copy-pasted by hand. Real commit messages from our repos:

> `Add Azure infrastructure (Bicep) following Easypark Integration pattern`
> `Use same method for deployment as Drive Intgration`
> `Homogenize: HTTP resilience, OpenTelemetry, version alignment`

Every one of those is a developer manually re-deriving a decision someone else already made.
That is what these skills replace.

## Install

```powershell
git clone https://dev.azure.com/autoplanas/Autoplan%20Development/_git/AutoplanCopilotSkills
cd AutoplanCopilotSkills
./scripts/Install-Skills.ps1
```

The script links every folder under `skills/` into `~/.agents/skills/`, which Copilot scans for
**all** repos — CLI, VS Code and the cloud agent. Symlinks are used when available (developer
mode / elevated), so `git pull` instantly updates your skills with no reinstall. Otherwise it
copies, and you re-run the script after pulling.

Verify with `/skills list` in Copilot CLI, or just ask for something that matches a trigger.

To remove: `./scripts/Uninstall-Skills.ps1`.

### Other agents

The skills themselves are **not Copilot-specific** — they are plain `SKILL.md` files in the open
Agent Skills format, with no vendor-specific frontmatter or tool bindings. Only the directory each
agent scans differs, so `-Target` installs the same clone anywhere:

```powershell
./scripts/Install-Skills.ps1 -Target Claude
./scripts/Install-Skills.ps1 -Target Copilot,Claude,Codex,Gemini
```

| Target | Installs into |
|---|---|
| `Copilot` (default) | `~/.agents/skills/` |
| `Claude` | `~/.claude/skills/` |
| `Codex` | `~/.codex/skills/` |
| `Gemini` | `~/.gemini/skills/` |

`Uninstall-Skills.ps1` takes the same `-Target`. Both default to Copilot, so existing usage is
unchanged.

One caveat: the checker scripts in `scripts/` are PowerShell. They run anywhere `pwsh` is installed,
but on a machine without it the skills that reference them still read fine — the prose stands on its
own, you just lose the automated check.

## Skills

| Skill | Use it when |
|---|---|
| `autoplan-integration-scaffold` | Starting a new integration, or aligning an existing one to the house standard |
| `autoplan-external-api-client` | Writing or reviewing the client that calls a third-party API |
| `autoplan-integration-auth` | Wiring authentication — inbound or outbound |
| `autoplan-integration-review` | Auditing an integration against the house standard |
| `autoplan-sql-model-alignment` | Adding or changing a field that must reach SQL, or debugging why one didn't |
| `autoplan-data-persistence` | Designing table entities and keys, batch upserts, blob archival, storage DI |
| `autoplan-azure-deploy` | Writing or changing `infra/main.bicep`, app settings, environments, provisioning |
| `autoplan-devops-pipeline` | Writing or changing `azure-pipelines.yml`, deploy stages, CI testing |
| `autoplan-integration-testing` | Writing unit tests, faking HTTP or Table Storage, deciding what is worth testing |
| `autoplan-integration-docs` | Writing a README or `DOCUMENTATION.md`, documenting an API, cleaning up doc sprawl |

All four tiers are complete. See `docs/roadmap.md` for how each skill was derived.

## Layout

```
skills/<skill-name>/
  SKILL.md              # frontmatter + short instructions; always loaded when triggered
  references/*.md       # depth, loaded on demand
  references/templates/ # copy-paste-ready files
```

`SKILL.md` stays short on purpose. Copilot loads it when the skill triggers and only pulls in
`references/` when it needs the detail, so bloating `SKILL.md` costs context on every activation.

## Checker scripts

`scripts/` also holds standalone checks the skills point at. They take a path and print findings;
none of them modify anything.

| Script | Finds |
|---|---|
| `Check-SqlParameterAlignment.ps1` | `@parameters` with no matching model property (runtime failure), and model properties never passed to SQL (silent data loss). Pass **every** model the service binds to, or you get false positives. |
| `Check-SqlDdlInDml.ps1` | `CREATE TABLE` column definitions leaked into a `MERGE`/`UPDATE`/`INSERT` — invalid T-SQL that compiles fine in C#. |
| `Check-BicepBaseline.ps1` | Missing items from the 15-point Function App baseline, and parameters that look like secrets but lack `@secure()`. |
| `Check-PipelineTestEnforcement.ps1` | Test steps that don't gate a deployment — commented-out test tasks, orphaned `PublishTestResults`, queue-time skip switches. |
| `Check-PipelineDeployGating.ps1` | `Deploy*`/`Update*Config` stages whose condition omits `ne(variables['Build.Reason'], 'PullRequest')` — meaning a PR validation build would deploy to production. Also flags `pr:` triggers, which Azure Repos Git ignores. |
| `Check-TestSuiteHealth.ps1` | Zero-byte test files, test projects with no `[Fact]`, non-reserved hostnames in tests. |
| `Check-DocsHygiene.ps1` | Episodic `*_SUMMARY`/`*_FIX`/`FINAL_*` documents, the untouched Azure DevOps README template, missing `DOCUMENTATION.md`. |

All seven found live defects on first use; see [`docs/changes.md`](docs/changes.md).

## Documentation

| Document | What it covers |
|---|---|
| [`docs/changes.md`](docs/changes.md) | **Every change made during the engagement** — the nine commits across five integration repos, what was wrong and how each fix was verified, what was deliberately left alone, and what still needs a human. |
| [`docs/roadmap.md`](docs/roadmap.md) | The numbered issue list (1–13), the four skill tiers, and the decisions taken. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to change a skill. |

## Scope note

These skills cover **our conventions**. They deliberately do not restate Azure basics — the
Microsoft `azure-*` skills already do that, and the `autoplan-*` prefix keeps the two from
colliding.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: a pattern earns its way in by
appearing in real code, and every claim cites the repo and file it came from.
