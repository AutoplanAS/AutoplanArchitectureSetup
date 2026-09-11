# Roadmap

Ten skills in four tiers, derived from an analysis of eight Autoplan integration repositories.
Tiers 1 and 2 are complete; the rest is the backlog.

For what was actually *changed* — the commits, their verification, and the open pull requests — see
[`changes.md`](changes.md).

## Where this came from

Every integration is the same shape: .NET 8 Azure Functions on the isolated worker, central package
management, a typed HTTP client onto a third-party vehicle or CRM API, persistence to Azure Table
Storage and/or SQL, Bicep IaC, a multi-stage Azure DevOps pipeline, xUnit + Moq.

A house standard already exists — but it is propagated by hand. Actual commit messages:

- `Add Azure infrastructure (Bicep) following Easypark Integration pattern` (Echoes)
- `Use same method for deployment as Drive Intgration` (Easypark)
- `Homogenize: HTTP resilience, OpenTelemetry, version alignment` (Echoes)

These skills replace that copy-paste propagation.

## Maturity at time of analysis

Superseded by the verified per-repo baseline in
`skills/autoplan-integration-review/references/current-state.md`, which was measured directly rather
than summarised. Two figures below were corrected there: HubSpot has 18 root-level `.md` files (38
repo-wide), and OFV does have `ValidateOnStart` and OpenTelemetry.

| Repo | Docs | Tests in CI | IaC | Pipeline | Config validation | Resilience | Telemetry |
|---|---|---|---|---|---|---|---|
| **Echoes** | 130+ line DOCUMENTATION.md | ✅ | ✅ Bicep | ✅ 6 stages | ✅ ValidateOnStart | ✅ Http.Resilience | OpenTelemetry |
| Easypark | README | ❌ commented out | ✅ Bicep | ✅ 5 stages | ❌ | ❌ | App Insights |
| HubSpot | 18 root .md files | ⚠️ 3 tests | ✅ Bicep | ✅ | ❌ | custom retry | App Insights |
| Drive / SmartCar | docs/ folder | ✅ | ✅ Bicep | ✅ | ✅ | ⚠️ opt-in | App Insights |
| Autoplan API | README | ❌ none | ❌ none | ❌ none | ✅ ValidateOnStart | ❌ | OpenTelemetry |
| OFV | 1-line README | ❌ disabled | ✅ Bicep | ✅ | ⚠️ | ❌ | App Insights |
| Vercel Vehicle API | boilerplate only | — | — | — | — | — | — |
| Platform wiki | empty boilerplate | — | — | — | — | — | — |

**EchoesIntegration is the canonical reference implementation.** The skills encode its patterns as
the default and treat the others as migration targets.

## Issues found during analysis

None of these is a skill. All need fixing independently of this work.

1. ⛔ **`OFVIntegration/local.settings.json` is tracked in git** and `.gitignore` does not exclude it. It contains a live API username and password for `https://integrasjon-ofv.qanto.no`. Verified with `git ls-files` and `git show HEAD:...`. Rotate the credential, `git rm --cached`, add the ignore rule, audit history. See `autoplan-integration-auth/references/secrets-management.md`.
   **✅ Fixed in OFVIntegration `c5b5187`** — untracked and `.gitignore` rule added. History audit: the file was introduced in the initial commit `967a2b4` and the password has **never** been changed since, so exactly one credential is exposed. A cross-check of all seven repos confirmed OFV is the only one affected. **The credential is still reachable in history and must be rotated regardless — that action, and any history rewrite, remain outstanding for the team.**
2. ⛔ **HubSpot deals are never saved to SQL, and the sync reports success.** Three compounding faults in committed code: `SqlDatabaseService.cs:432-445` has fourteen lines of `CREATE TABLE` column definitions pasted inside the deals MERGE's `WHEN MATCHED THEN UPDATE SET` clause (invalid T-SQL, the statement cannot execute); lines 492-497 swallow the exception with `//throw;` commented out and a `"DO NOT THROW EXCEPTION FOR NOW"` log line — deals is the only entity that swallows; `HubSpotSyncOrchestrationService.cs:101` then returns `Success = true` with `DealsProcessed = deals.Count`, the number *retrieved*, not saved. Full write-up in `autoplan-sql-model-alignment/references/known-defects.md`.
   **✅ Fixed in Hubspot Integration `a8519ab`** — the DDL was replaced with 37 `Column = @Param` assignments and `throw;` was restored. Proven with Microsoft's `ScriptDom` `TSql160Parser`: the committed statement fails with `Incorrect syntax near 'NVARCHAR'`, so it had never once executed; the fixed statement parses. The five MERGE statements were extracted into `SqlStatements.cs` and are now guarded by 15 tests (`SqlStatementsTests.cs`) asserting each parses as valid T-SQL, assigns every inserted column, and has no duplicate assignments. The guard was itself verified by re-injecting the defect — exactly the three `MergeDeals` cases failed. `DealsProcessed = deals.Count` is left as-is; restoring `throw;` means a save failure now fails the run.
3. ⚠️ **Drive's dealer attribution never reaches SQL.** `SalesContractEntity.ForhandlerNavn` and `ForhandlerNummer` (lines 28, 32) are populated from `driveOrder.DealerName`/`DealerNumber` (`Models/SalesContractEntity.cs:575-576`) but appear in neither `MergeSalesContractSql` nor `SalesContractsSqlInitializer.cs`. The data reaches Table Storage and stops there. Found by `scripts/Check-SqlParameterAlignment.ps1`.
   **✅ Fixed in Drive Integration `3e68823`** — both columns added to the `CREATE TABLE`, to the MERGE (`UPDATE SET`, `INSERT`, `VALUES`) and bound in `StoreSalesContractInSqlAsync`, plus a guarded `AlterSalesContractsColumnsSql` following the existing AdInventory `IF NOT EXISTS (sys.columns) … ALTER TABLE ADD` pattern so already-deployed tables gain the columns. Verified: all 8 SQL constants parse under ScriptDom, all 95 MERGE parameters have a matching `AddParameter` call, and `UPDATE` assigns every inserted column except the `Id` merge key.
4. ⚠️ **Easypark's pipeline has `dotnet test` commented out** (`Easypark Integration/EasyparkIntegration/EasyparkIntegration/azure-pipelines.yml`, lines 60-64) while `PublishTestResults@2` still runs at line 66 — a green test step that executed nothing. The repo has ten test files. Confirmed by `scripts/Check-PipelineTestEnforcement.ps1`.
   **✅ Fixed in Easypark Integration `55d7f49`** — the test task is re-enabled with `publishTestResults: false` (the existing `PublishTestResults@2` step owns publishing) and `failTaskOnMissingResultsFile: true`, so an empty run can no longer report green. The suite was verified locally at **40 passing tests**. Note: the local build fails with MSB3030 for an unrelated reason — a generated `WorkerExtensions` path 262 characters long against Windows' 260-character limit with `LongPathsEnabled=0`. CI is unaffected (Linux agents).
5. ⚠️ **Half the estate does not run tests in CI.** Drive (lines 72-84) and OFV (lines 66-78) have both the test task and its publish step commented out; Easypark is the case above. Only Echoes, HubSpot and SmartCar run tests, and HubSpot's can be skipped at queue time.
6. ⚠️ **No pipeline validates a pull request.** A branch is first built after it is merged. **Correction to earlier guidance in this document: adding a `pr:` trigger to the YAML does not fix this.** Microsoft's documentation is explicit that for Azure Repos Git, PR triggers "[are] implemented using branch policies" and the YAML `pr:` key is ignored. The correct control is a **Build Validation branch policy** per pipeline, created with `az repos policy build create`. See "Enabling PR validation" below for the prerequisite and the exact commands.
7. ⚠️ **The managed identity grants nothing.** All six Bicep templates declare `identity: { type: 'SystemAssigned' }` and not one contains a `Microsoft.Authorization/roleAssignments` resource. All data access is by account key. This is the cheapest available hardening — the identity is already there.
8. ⚠️ **A document claims a fix that does not exist in the code.** `Hubspot Integration/SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md` states `SqlDatabaseService.cs` was "recreated from scratch" with "correct parameter mappings"; lines 432-445 still contain the DDL. Anyone who read it concluded the deals bug was handled.
9. ⚠️ **Two test files are zero bytes** — `DriveFunctions.Tests/WaykeGraphQLLookupClientTests.cs` and `EasyparkIntegration.Tests/Services/EasyparkFleetApiClientTests.cs`. `OFVIntegration.Tests` contains zero `[Fact]`s. Confirmed by `scripts/Check-TestSuiteHealth.ps1`.
10. ⚠️ **Three repos still have the untouched Azure DevOps default README template** (Easypark, AutoplanAPIIntegration, Vercel Vehicle API), and OFV's README is a single heading. The platform wiki's three markdown files are all zero bytes.
11. ⚠️ **Drive has a failing test committed on `master`.** `SalesContractEntityDriveOrderMappingTests.Constructor_MapsFinanceAndInsurance_WithinExistingFields` asserts `entity.Forsikringsselskap == "DNB"` but the value is `null` — a FINANCING order line's `FinancialInstitution` is expected to land in the *insurance company* field. Verified as pre-existing by running the suite against pristine `HEAD` (35 passed, 1 failed, identical with and without our change). Not fixed here: the assertion is semantically ambiguous and needs product input on whether a financing institution belongs in `Forsikringsselskap`. **This is direct evidence of the cost of issue 5** — a red test has sat on `master` unnoticed precisely because Drive's pipeline does not run tests.
12. ⛔ **No deploy stage was gated on branch or build reason, so PR validation would have deployed to production.** Every one of the six pipelines defines `deployDevInfra`/`deployProdInfra` with `default: true`, and each `Deploy*`/`Update*Config` stage's condition tests only those parameters and the preceding stage's result — never the branch or the build reason. A build validation policy runs the whole YAML against the PR merge commit, so `Build → DeployDevApp → DeployProdApp` would have run and pushed unreviewed pull-request code to production. There is no downstream safety net either: **all twelve environments, including the six `-prod` ones, have zero approval checks.** Independently of PR validation, this also means a manual queue on any branch deploys that branch to production. **✅ Fixed on branches** — `ne(variables['Build.Reason'], 'PullRequest')` added as the first condition of all 28 `Deploy*`/`Update*Config` stages (Drive `82a3e2b`, Easypark `e363030`, HubSpot `7962bcc`, OFV `d3eae61`, Echoes `30cdb1f`). CI, manual and scheduled behaviour is unchanged.
13. ⚠️ **Drive Integration and SmartCar Integration have a dead CI trigger.** Both pipelines declare `trigger: branches: include: - main`, but the `Drive Integration` repository has no `main` branch — its default is `master`. Their CI therefore never fires: every run in the pipeline history is `reason=manual`, going back to March. Not fixed here — repointing the trigger to `master` would turn on automatic build *and deploy to production* for a repo that has been manually deployed for months. That is a team decision, not a typo fix.

## Open pull requests

All fixes are on branch `joergenamrudhagen-turbo-waffle` in each repo. Nothing is merged.

| PR | Repo | Target | Contains |
|---|---|---|---|
| !7 | Drive Integration | `master` | issue 2 (dealer attribution) + issue 12 (gating) |
| !8 | Easypark Integration | `main` | issue 3 (tests in CI) + issue 12 |
| !9 | Hubspot Integration | `main` | issue 1 (deals MERGE) + issue 12 |
| !10 | OFVIntegration | `master` | issue 4 (committed credentials) + issue 12 |
| !11 | EchoesIntegration | `main` | issue 12 |

All five merge cleanly. **Merging deploys to production**, because CI on the default branch runs
`Build → DeployDevApp → DeployProdApp` and no environment has an approval check. Merge deliberately,
and merge these before creating any Build Validation policy.

## Enabling PR validation

`pr:` in YAML is ignored for Azure Repos Git. PR validation is a **Build Validation branch
policy** on the target branch.

**Prerequisite — do not create these policies until issue 12's fix is merged into each
default branch.** A validation build runs the YAML from the *merge commit* (source merged
into target). Until the `Build.Reason` guard is present on `main`/`master`, a pull request
opened from a branch that lacks the guard would still deploy to production. Merge first,
then run these.

Verify the prerequisite is actually met before running the block — do not take it on trust:

```powershell
# must report OK for every pipeline, against the default branch, not a feature branch
.\scripts\Check-PipelineDeployGating.ps1 -Path <each repo>
```

Note the default branch differs per repo: `master` for Drive and OFV, `main` for the rest.

```powershell
$org  = "https://dev.azure.com/autoplanas"
$proj = "Autoplan Development"

# name, repository-id, branch, build-definition-id
$policies = @(
  @{ n='Drive Integration';    r='51c3d10c-8d80-4aa5-bf26-15b2e66f2c72'; b='master'; d=4  }
  @{ n='SmartCar Integration'; r='51c3d10c-8d80-4aa5-bf26-15b2e66f2c72'; b='master'; d=6  }
  @{ n='Easypark Integration'; r='5adbf12c-399b-4d81-b5f0-4fd6bfea8214'; b='main';   d=7  }
  @{ n='Hubspot Integration';  r='6479a74d-1f58-48f8-a7bf-4423fcecfa5f'; b='main';   d=8  }
  @{ n='OFVIntegration';       r='e4248ffe-9486-43d3-b3d5-42042ff6701c'; b='master'; d=11 }
  @{ n='EchoesIntegration';    r='3af22834-c2e7-4b24-b9fc-ab3a1b1a469a'; b='main';   d=12 }
)

foreach ($p in $policies) {
  az repos policy build create --org $org --project $proj `
    --repository-id $p.r --branch $p.b --build-definition-id $p.d `
    --display-name "PR validation - $($p.n)" `
    --blocking true --enabled true `
    --manual-queue-only false --queue-on-source-update-only true `
    --valid-duration 720
}
```

Two caveats worth knowing: draft pull requests do not trigger a policy build, and creating
these policies requires project administrator rights.

## Tier 1 — Foundation ✅ complete


**`autoplan-integration-scaffold`** — solution layout, `Directory.Build.props`,
`Directory.Packages.props` with pinned house versions, `NuGet.config` workaround for Functions
Worker SDK issue #1888, `Program.cs` DI wiring, options validation, `.gitignore` and
`local.settings.example.json`.
*Sources: Echoes (canonical), Easypark, Autoplan API.*

**`autoplan-external-api-client`** — typed clients, `Microsoft.Extensions.Http.Resilience` standard
handler, RFC 9457 problem-details parsing, the pagination catalogue (offset/limit with early exit,
cursor, request-handle two-step), null-vs-throw semantics, and the API quirks we work around.
*Sources: Echoes, Easypark, OFV, Autoplan API.*

**`autoplan-integration-auth`** — decision table plus recipes for OAuth2 client credentials with a
cached token service, dual-token renewal through a `DelegatingHandler`, authorization-code flow with
per-user token storage, inbound function/header/HMAC auth, and secrets management.
*Sources: Autoplan API, Echoes, Drive/SmartCar.*

## Tier 2 — Data ✅ complete

**`autoplan-data-persistence`** — Table Storage entity conventions (partition/row key design,
denormalised join keys, UTC-only timestamps, transactional batch upserts, supported EDM types and
the silent `decimal` trap), blob archival of raw payloads for replay, multi-target write
orchestration with per-item error isolation, keyed DI for multi-account storage.
*Sources: Easypark, Drive, Echoes, HubSpot.*

> Two claims in the original plan did not survive contact with the source and were dropped:
> **429 throttling handling does not exist in any storage code** (only in HubSpot's HTTP client), and
> **blob archival exists only in Drive** — Echoes stores raw JSON in a table column, not a blob.
> Both are now documented as gaps rather than patterns.

**`autoplan-sql-model-alignment`** — the most expensive lesson in the codebase; HubSpot burned six
documents on it. The three-layer model contract (API types → table entities → DB models) and what
may drop at each layer; MERGE parameter ↔ model property alignment as a contract that compiles fine
in C# and fails at runtime in SQL; type mapping rules (`DECIMAL(18,2)` for money, `DATETIMEOFFSET`
for dates, nullable wherever the API can return null); idempotent schema scripts and post-deploy
verification.
*Sources: HubSpot `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md`, `SQLDATABASESERVICE_UPDATE.md`,
`MAPPINGSERVICE_UPDATE.md`, `sql/README.md`; Drive.*

> Building this skill uncovered four live defects, documented with citations in its
> `references/known-defects.md`. The most serious is listed under **Findings** above.

## Tier 3 — Delivery ✅ complete

**`autoplan-azure-deploy`** — the house Bicep template (Log Analytics → App Insights → host storage
→ data storage → consumption plan → Function App → diagnostic settings and metric alerts), naming
conventions, the shared-vs-dedicated data storage toggle for dev cost control, `@secure()`
parameters with secrets injected at deploy time, `provision.ps1`.
*Sources: Echoes, Easypark, HubSpot, Drive, SmartCar, OFV.*

> **All six templates pass the full 15-point baseline.** The Bicep is by a wide margin the most
> consistent artifact in the estate — same seven resource types, same hardening, same region, same
> SKU. The gaps are uniform rather than divergent: no Key Vault, no role assignments for the
> declared managed identity, no SQL in IaC, and two HTTP-shaped alerts that a timer-triggered app
> cannot trip.

**`autoplan-devops-pipeline`** — the five-stage pattern with prod gated on a successful dev app
deploy; artifact separation so config-only redeploys are possible; when `bash: dotnet test` is
required over `DotNetCoreCLI@2` and when it is not; never a commented-out test task beside a live
`PublishTestResults`.
*Sources: Echoes (237 lines), Easypark (225), OFV (283), HubSpot (236), Drive (389), SmartCar (239).*

> The roadmap's original claim that `bash: dotnet test` should always replace `DotNetCoreCLI@2` was
> **narrowed after checking the source**. Worker SDK issue #1888 bites only when the repo has its own
> `NuGet.config` — and Echoes is the only repo that does. SmartCar and HubSpot run
> `DotNetCoreCLI@2 test` successfully. The skill states the condition rather than the blanket rule.

## Tier 4 — Quality and knowledge ✅ complete

`autoplan-integration-review` was pulled forward and built ahead of Tiers 2–3, because it flags the
two live issues above automatically and gives every other skill a scoring rubric.

**`autoplan-integration-testing`** ✅ — xUnit + Moq, the three HTTP handler fakes actually in use and
when each is correct, faking `AsyncPageable`/`Page` (which Moq cannot construct), what is worth
testing, and the limit of a mocked boundary.
*Sources: Echoes (47 tests), Drive + SmartCar (38), Easypark (29), HubSpot (3), OFV (0).*

> **HubSpot's test suite asserts precisely the behaviour that is broken, and passes.**
> `HubSpotSyncOrchestrationServiceTests.cs:87` verifies `SaveDealsAsync` was called `Times.Once`.
> `ISqlDatabaseService` is a mock, so the DDL-in-MERGE defect inside the real method is never
> executed. Line 75's `DealsProcessed` assertion passes for the same reason the orchestrator reports
> success: the count is of deals *retrieved*. This is now the worked example for the skill's central
> rule — a mock verifies a call, and the defect was inside the callee.

**`autoplan-integration-docs`** ✅ — the two-file standard (`readme.md` + `DOCUMENTATION.md`) lifted
from Echoes, the keep/discard rule for episodic documents, verified-versus-assumed labelling, the
decisions log, and seed content for the empty platform wiki.
*Sources: Echoes (468 lines across 2 files), HubSpot (4,562 across 18), Drive, OFV.*

> The roadmap's "18 root-level status reports" was verified exactly: 18 files, 4,562 lines, of which
> `Check-DocsHygiene.ps1` flags 14 as episodic by filename. Worse than the volume is that
> `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md` claims `SqlDatabaseService.cs` was "recreated from
> scratch" with "correct parameter mappings" — while lines 432-445 still contain the DDL. The
> earlier, honest `SQL_PARAMETER_FIX.md:38` said the other save methods "should be reviewed"; the
> later, more confident document buried that caveat.

**`autoplan-integration-review`** ✅ — audit an existing integration against the house standard and
output a prioritised gap list. Encodes every anti-pattern found, the exact commands for each check,
the ten ways those checks produce false positives, and a verified per-repo baseline. Doubles as the
migration driver for OFV, Easypark, Autoplan API and Vercel Vehicle API.

## Build order for the remainder

All four tiers are built. Remaining work is adoption, not authoring:

1. ~~Fix the four live defects above~~ ✅ **done** — HubSpot `a8519ab`, Easypark `55d7f49`,
   Drive `3e68823`, OFV `c5b5187`. The OFV credential still needs rotating by the team.
2. Re-enable the disabled test steps in Drive, OFV and Easypark — 67 written, passing tests
   currently gate nothing.
3. Merge the deploy gating (issue 12), then create the Build Validation branch policies —
   see "Enabling PR validation". The `pr:` trigger approach does not work on Azure Repos.
4. Migrate Easypark, HubSpot and Drive to OpenTelemetry (decision 1 below), adding a run-failure
   alert while the telemetry is being touched. OFV is already on OpenTelemetry.
5. Run `autoplan-integration-review` against OFV, Easypark and AutoplanAPIIntegration to drive them
   onto the house standard. Vercel Vehicle API is greenfield — scaffold rather than review.

## Decisions

Resolved 2026-08-19.

### 1. OpenTelemetry is the telemetry standard

Confirmed. The Tier 1 skills already assume it and the scaffold templates already produce it.

Measured 2026-08-19 by reading each `Program.cs`, `.csproj` and `host.json` — the split is **3/3,
not 2/4**:

| Stack | Repos |
|---|---|
| OpenTelemetry | Echoes, AutoplanAPIIntegration, **OFV** |
| `Microsoft.ApplicationInsights.WorkerService` | Easypark, HubSpot, Drive |

OFV is already on the modern stack (`AddOpenTelemetry()`, the three OTel packages, and
`"telemetryMode": "OpenTelemetry"` in `host.json`). An earlier draft of this roadmap listed OFV as
needing migration; that was wrong and is corrected here.

**Easypark, HubSpot and Drive migrate as a tracked piece of work** — not opportunistically. Three
repos, each needing the OpenTelemetry wiring in `Program.cs`, the `telemetryMode` line in
`host.json`, and `Microsoft.ApplicationInsights.WorkerService` removed. Raise one work item per repo
so the state of each is visible. `autoplan-integration-scaffold/references/program-cs.md` has the
target wiring.

Note this interacts with the alerting gap: the two baseline metric alerts are HTTP-shaped and cannot
fire for a timer-triggered function (`autoplan-azure-deploy/references/gaps.md`). Migrating telemetry
is the natural moment to add a "no successful run in N hours" alert, because that is the signal that
would have caught the HubSpot deals failure.

### 2. No shared NuGet package

Rejected. A shared package would couple the integrations to each other, and independence is worth
more than removing the duplication.

Consequence: **the skills repo is the distribution mechanism for these patterns.** Where a package
would have given one place to fix a bug, we instead rely on the skill being accurate and on
`autoplan-integration-review` finding drift. That raises the bar on this repo — a wrong pattern here
propagates by hand-copy exactly as it did before, so every claim stays evidence-backed with a
file:line citation.

The known duplication stands and is accepted: `MockHttpMessageHandler` exists twice with different
designs, plus a third inline `SequenceHandler`. Documented in
`autoplan-integration-testing/references/http-fakes.md`, which explains when each is the right
choice rather than treating the divergence as an error.

### 3. Vercel Vehicle API is in scope

It is a planned integration, currently one commit containing only the default README template — no
code at all. When someone starts it, they scaffold from `autoplan-integration-scaffold` and follow
the house pattern. No migration work; it is a greenfield case, and the first real test of whether
the scaffold skill produces a compliant integration from nothing.
