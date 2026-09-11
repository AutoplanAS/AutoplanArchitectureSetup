# Change record

Everything changed during the skills engagement, 2026-08-19. Written so that a reviewer can check
each claim rather than take it on trust.

Two companion documents:

- [`roadmap.md`](roadmap.md) — the numbered issue list (1–13), the four skill tiers, and the
  decisions taken.
- [`../README.md`](../README.md) — what the skills repository is and how to install it.

**Nothing in the integration repositories is merged.** All nine commits sit on
`joergenamrudhagen-turbo-waffle` behind five pull requests. See [Open pull
requests](#open-pull-requests).

---

## Part 1 — Changes to the integration repositories

Nine commits across five repositories.

| Repo | Commit | Change | Issue |
|---|---|---|---|
| OFVIntegration | `c5b5187` | Stop tracking `local.settings.json` | 1 |
| Hubspot Integration | `a8519ab` | Fix the deals MERGE, restore the rethrow, extract and guard the SQL | 2 |
| Drive Integration | `3e68823` | Persist `ForhandlerNavn` / `ForhandlerNummer` to SQL | 3 |
| Easypark Integration | `55d7f49` | Actually run the tests in CI | 4 |
| Drive Integration | `82a3e2b` | Gate 6 deploy stages on build reason (2 pipelines) | 12 |
| Easypark Integration | `e363030` | Gate 4 deploy stages on build reason | 12 |
| Hubspot Integration | `7962bcc` | Gate 4 deploy stages on build reason | 12 |
| OFVIntegration | `d3eae61` | Gate 6 deploy stages on build reason | 12 |
| EchoesIntegration | `30cdb1f` | Gate 4 deploy stages on build reason | 12 |

Issue numbers refer to [`roadmap.md`](roadmap.md#issues-found-during-analysis). The subsections below
follow that numbering rather than the order the work was done in.

### Issue 1 — OFV: live credentials in git

`c5b5187` — 2 files, +4 / −13.

`local.settings.json` was tracked and contained a real `OFV__Username` and `OFV__Password`.
`git rm --cached` plus a `.gitignore` rule.

History audit: introduced in the initial commit `967a2b4`, and **exactly one distinct password value
has ever existed** — it has never been rotated. All seven repositories were checked; OFV is the only
one affected.

> ⚠️ **This commit does not remediate the exposure.** The credential is still readable at `967a2b4`
> by anyone with repository access. **It must be rotated.** See
> [What still needs a human](#part-4--what-still-needs-a-human).

### Issue 2 — HubSpot: a MERGE that had never executed once

`a8519ab` — 6 files, +434 / −275.

The deals MERGE statement had fourteen lines of `CREATE TABLE` column definitions pasted inside its
`WHEN MATCHED THEN UPDATE SET` clause. That is invalid T-SQL, so the statement threw on every single
execution since it was written. The exception was caught and swallowed, so the sync reported success
and no deal ever reached the database.

Proven rather than inferred: parsed with `TSql160Parser`, the committed statement fails with
`Incorrect syntax near 'NVARCHAR'`, so it had never once executed. The fixed statement parses.

Three things were wrong and all three are fixed:

- **The statement.** The DDL replaced with 37 `Column = @Param` assignments.
- **The swallow.** `throw;` restored, so the next failure of this kind surfaces instead of hiding.
- **The absence of any guard.** The five MERGE statements moved out of `SqlDatabaseService.cs` into a
  new `SqlStatements.cs` (296 lines), and `SqlStatementsTests.cs` added — three `MemberData`-driven
  theories, 15 test cases, parsing *every* statement with
  `Microsoft.SqlServer.TransactSql.ScriptDom` and asserting each assigns every inserted column with
  no duplicates. A malformed statement now fails the build rather than reaching production.

Extracting the SQL was what made the guard possible; the tests cannot reach a string that is inlined
in a method body. The guard was itself verified by re-injecting the original defect — exactly the
three `MergeDeals` cases failed, and no others.

**No backfill is required.** `FullSyncTimerTrigger` runs `0 0 2 * * 0` — Sundays at 02:00 — and calls
`ExecuteFullSyncAsync`, so the missing deals repopulate within a week of deploy. That weekly job is
the thing to watch to confirm the fix landed.

### Issue 3 — Drive: dealer attribution mapped but never stored

`3e68823` — 2 files, +21 / −4.

`ForhandlerNavn` and `ForhandlerNummer` were populated on `SalesContractEntity` and then silently
dropped: both were absent from the `CREATE TABLE` and from the MERGE. Fixed in three places, because
a schema change alone would not have helped an existing database:

- Added both columns to the `CREATE TABLE`.
- Added a new `AlterSalesContractsColumnsSql` constant using the guarded-`ALTER` pattern already
  established for AdInventory, wired into `StartAsync`, so deployed databases pick the columns up.
- Added both to the MERGE `UPDATE SET`, `INSERT` and `VALUES`, plus their `AddParameter` bindings.

Verified: all 8 SQL constants parse under ScriptDom; all 95 MERGE parameters have a matching
`AddParameter` call; the `UPDATE` assigns every `INSERT` column except the `Id` merge key.

### Issue 4 — Easypark: a green test step that ran nothing

`55d7f49` — 1 file, +9 / −6.

`dotnet test` was commented out while `PublishTestResults@2` still ran. Every build displayed a
"Publish test results" step and passed. The repository has forty tests, none of which had run in CI.

Re-enabled the test task, and set `failTaskOnMissingResultsFile: true` with `publishTestResults:
false` so the same silent failure cannot recur — if the results file is missing, the build now fails
instead of reporting success.

### Issue 12 — all six pipelines: deploy stages ungated on build reason

`82a3e2b`, `e363030`, `7962bcc`, `d3eae61`, `30cdb1f` — 28 stages across 6 pipeline files.

Every `Deploy*` and `Update*Config` stage condition tested only the deploy parameters and the
preceding stage's result. Nothing tested the branch or the build reason, and `deployDevInfra` /
`deployProdInfra` both default to `true`.

```yaml
# before
condition: and(succeeded('Build'), eq(${{ parameters.deployProdApp }}, true))

# after
condition: and(ne(variables['Build.Reason'], 'PullRequest'), succeeded('Build'), eq(${{ parameters.deployProdApp }}, true))
```

Two consequences, one live and one latent:

- **Live:** manually queueing any pipeline on any branch deploys that branch to production.
- **Latent:** enabling PR validation would have deployed *every pull request* to production, because
  a validation build runs the whole YAML against the merge commit.

There is no compensating control at the environment layer: **all twelve environments, the six
`-prod` ones included, have zero approval checks.** Verified through the `pipelinesChecks` API.

`Build.Reason` is `PullRequest` only for validation builds, so CI, manual and scheduled runs are
completely unaffected by the guard. It was preferred over a branch check because it is the narrowest
condition that makes PR validation safe, and it survives a default-branch rename.

This one is worth remembering as a pattern, not just a fix: the repositories had a correctly
identified gap (no PR validation), and the obvious remediation for that gap would have caused a far
worse outcome than the gap itself. Both facts were individually reasonable. Recorded as an
anti-pattern in `autoplan-integration-review/references/anti-patterns.md`.

---

## Part 2 — The skills repository

Created from scratch: **10 skills in 4 tiers, 7 checker scripts, 2 install scripts**, 12 commits.

| Tier | Skills |
|---|---|
| 1 Foundation | `autoplan-integration-scaffold`, `autoplan-external-api-client`, `autoplan-integration-auth`, `autoplan-integration-review` |
| 2 Data | `autoplan-sql-model-alignment`, `autoplan-data-persistence` |
| 3 Delivery | `autoplan-azure-deploy`, `autoplan-devops-pipeline` |
| 4 Quality | `autoplan-integration-testing`, `autoplan-integration-docs` |

Distribution is a shared Azure DevOps repository plus `scripts/Install-Skills.ps1`, which links each
skill folder into the selected agent's skills directory — `~/.agents/skills/` for Copilot by
default, with `-Target Claude|Codex|Gemini` for the others. It prefers symlinks and falls back to
copying; **in copy mode it must be re-run after every `git pull`**, and it says so on each run.

The skill content is vendor-neutral: plain `SKILL.md` files with `name`, `description`, `license`
and `metadata` frontmatter, no tool bindings and no Copilot-specific syntax. Nothing has to change
to use them from another agent — only the install path differs.

### Checker scripts

Each one exists because it found a real defect, not because it seemed like a good idea.

| Script | Found |
|---|---|
| `Check-SqlDdlInDml.ps1` | HubSpot's invalid deals MERGE (issue 2) |
| `Check-SqlParameterAlignment.ps1` | Drive's unstored dealer columns (issue 3) |
| `Check-PipelineTestEnforcement.ps1` | Easypark's green-but-empty test step (issue 4) |
| `Check-PipelineDeployGating.ps1` | 28 ungated deploy stages (issue 12) |
| `Check-BicepBaseline.ps1` | Gaps against the 15-point Function App baseline |
| `Check-TestSuiteHealth.ps1` | Zero-byte test files, test projects with no `[Fact]` |
| `Check-DocsHygiene.ps1` | Episodic `*_SUMMARY` docs, untouched README templates |

`Check-PipelineDeployGating.ps1` was validated in both directions before being trusted: **28 findings
across the six pre-fix revisions, zero on the current ones**, with exit codes 1 and 0 respectively.
A checker that has only ever been run against passing input has not been tested.

### Corrections applied to skill content

Two claims that were written into the skills and later disproved:

- **`pr:` triggers do not work on Azure Repos Git.** Microsoft's documentation states that for Azure
  Repos Git this "is implemented using branch policies". The `pr:` key is honoured for GitHub and
  Bitbucket only. Committing one produces a green diff, no error and no validation. The skills now
  carry the correct control (`az repos policy build create`) and mark `pr:` as do-not-use.
- **The prod environment is not a safety net.** Several skill files said to check the portal for the
  approval gate. The portal was checked: no environment has one. The files now state that.

The guard from issue 12 was also added to the canonical stage conditions in
`autoplan-devops-pipeline/references/stages.md`, so pipelines scaffolded from the skills are safe by
default rather than needing the fix applied afterwards.

---

## Part 3 — Found and deliberately not fixed

Each of these was investigated far enough to be sure it is real, then left alone for a stated reason.

| # | Finding | Why not fixed |
|---|---|---|
| 11 | Drive has a **failing test committed on `master`** — `Forsikringsselskap == "DNB"` asserts a FINANCING line's `FinancialInstitution` lands in the *insurance company* field, and the value is `null`. | Semantically ambiguous. Needs product input on whether a financing institution belongs in that field. Confirmed pre-existing by running the suite against pristine `HEAD`. |
| 13 | **Drive and SmartCar have a dead CI trigger.** Both trigger on `main`; the Drive repository's default branch is `master` and has no `main`. Their CI has never fired — every run in history is `reason=manual`, going back to March. | Repointing the trigger turns on automatic build *and production deploy* for a repo that has been manually deployed for months. A team decision, not a typo fix. |
| — | `HubSpotSyncOrchestrationService.cs:101,169` reports `DealsProcessed = deals.Count` — deals *retrieved*, not *saved*. This is part of why issue 2 stayed invisible. | Restoring `throw;` removes most of the risk. Changing the metric's meaning deserves its own review. |
| — | Easypark and HubSpot have no `.gitignore` rule for `local.settings.json`. Both are clean today, but unprotected. | Low risk, and unrelated to the branches in flight. |

Issue 11 is the clearest evidence of the cost of issue 5: a red test sat on `master` unnoticed
precisely because Drive's pipeline does not run tests.

---

## Part 4 — What still needs a human

Ordered by urgency.

1. ⛔ **Rotate the OFV credential.** `c5b5187` stops further exposure; it does not undo the exposure.
   The password is still readable at `967a2b4` and has never been changed.
2. **Merge the five pull requests** — see below. This is a deployment, not a formality.
3. **Create the Build Validation policies.** The ready-to-run command block, with every repository
   and definition ID, is in [`roadmap.md`](roadmap.md#enabling-pr-validation). **Only after step 2**,
   and confirm with `Check-PipelineDeployGating.ps1` run against the *default* branch first.
4. **Decide the Drive `DNB` assertion** (issue 11), then re-enable Drive's and OFV's test steps.
5. **Decide whether prod environments should require approval.** Today none do.
6. **Decide whether to repoint Drive/SmartCar triggers** from `main` to `master` (issue 13).
7. Set a branch policy on `AutoplanCopilotSkills/main`, and confirm the team has read access.

### Open pull requests

| PR | Repo | Target | Contains |
|---|---|---|---|
| !7 | Drive Integration | `master` | issue 3 + issue 12 |
| !8 | Easypark Integration | `main` | issue 4 + issue 12 |
| !9 | Hubspot Integration | `main` | issue 2 + issue 12 |
| !10 | OFVIntegration | `master` | issue 1 + issue 12 |
| !11 | EchoesIntegration | `main` | issue 12 |

All five merge cleanly. Note the target branch differs: `master` for Drive and OFV, `main` for the
rest.

> ⚠️ **Merging is deploying.** CI on the default branch runs `Build → DeployDevApp → DeployProdApp`,
> and no environment has an approval check. Merging any of these pushes to production immediately.
> This is exactly what issue 12's fix prevents for *pull request* builds — it does not, and should
> not, change what a merge does.

---

## Part 5 — How things were verified

The working rule was that a grep hit is a lead, not a finding, and nothing was reported without
opening the file or querying the live system. It was worth the cost: **six claims made during this
engagement were later disproved by that check**, including two of the recommendations themselves.

| Claim | Verified by |
|---|---|
| The deals MERGE is invalid T-SQL | Parsed with ScriptDom; now a permanent test |
| Drive's dealer columns never reach SQL | Compared all 95 MERGE parameters against `AddParameter` calls |
| Drive's test failure is pre-existing | Restored both files from `HEAD` into a scratch copy, re-ran: identical 35 passed / 1 failed |
| The OFV password was never rotated | Walked every revision of the file through history |
| No environment has an approval | `pipelinesChecks` API, all twelve environments |
| `pr:` does not work on Azure Repos Git | Microsoft's own documentation, after the claim was doubted |
| Drive/SmartCar CI has never fired | Every run in the pipeline history is `reason=manual` |
| Echoes' four cancelled builds are benign | Timestamps plus `lastChangedBy = Microsoft.VisualStudio.Services.TFS` — superseded CI runs |
| The deploy gating checker works | 28 findings pre-fix, 0 post-fix |

### Corrections made to earlier claims

Recorded because the corrections are as useful as the findings:

- OFV **does** use OpenTelemetry — the split is 3/3, not 2/4.
- Easypark has 40 tests, not 29.
- Drive's dealer mapping lives in `Models/SalesContractEntity.cs`, not `DriveTableStorageService.cs`.
- AutoplanAPIIntegration has no pipeline at all.
- `pr:` triggers are ignored on Azure Repos Git.
- PR validation is not a self-contained change; it requires the deploy gating first.

---

## Part 6 — Environment notes

Facts about this project worth not rediscovering.

**Azure DevOps** — org `https://dev.azure.com/autoplanas`, project `Autoplan Development`:

| Pipeline | Definition | Repository | Default branch |
|---|---|---|---|
| Drive Integration | 4 | Drive Integration | `master` |
| SmartCar Integration | 6 | Drive Integration | `master` |
| Easypark Integration | 7 | Easypark Integration | `main` |
| Hubspot Integration | 8 | Hubspot Integration | `main` |
| OFVIntegration | 11 | OFVIntegration | `master` |
| EchoesIntegration | 12 | EchoesIntegration | `main` |

Twelve environments, `<integration>-dev` and `<integration>-prod`, none with any check configured.

**Windows build traps** encountered repeatedly:

- **MAX_PATH.** Easypark's generated `WorkerExtensions` path is 262 characters against a 260 limit,
  surfacing as MSB3030 with no root cause logged. The diagnostic tell is that `Get-ChildItem` lists
  the file while `Test-Path` returns `$false`. Workaround: `robocopy /E /XD obj bin .git .vs` to a
  short path. CI is unaffected — the agents are Linux.
- **git writes progress to stderr,** so a successful `push`, `clone` or `worktree add` surfaces in
  PowerShell as `NativeCommandError`. Confirm with `git status -sb`, never the exit code.
- **`git commit -m` can silently fail** when the message contains embedded double quotes — staged,
  uncommitted, no error if output was piped away. Always confirm with `git log --oneline -1`.
- **Incremental-build timestamps.** A file restored via `Copy-Item` or `git show >` can be older than
  the compiled assembly, so MSBuild skips recompiling it and the test run is stale.
- **PowerShell variable names are case-insensitive.** A loop variable `$target` is the *same
  variable* as a parameter `$Target`. If that parameter carries `[ValidateSet]`, the assignment
  inside the loop is validated against the set and throws — reported against the parameter, far from
  the line at fault. Caught when `-Target` was added to `Install-Skills.ps1`; the loop variable was
  renamed to `$skillPath`.
