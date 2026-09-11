# Known defects in this estate

Live defects found while building this skill, verified against committed code on 2026-08-19. Each
is a worked example of a rule in the SKILL. Fix them; do not copy them.

## 1. HubSpot deals are never saved to SQL, and the sync reports success

**Severity: critical.** Three separate faults compound into silent data loss.

### Fault A -- DDL pasted into a DML statement

`HubSpotDataRetriever/Services/SqlDatabaseService.cs`, lines 432-445, inside the
`WHEN MATCHED THEN UPDATE SET` clause of the deals MERGE:

```sql
AnalyticsLatestSourceTimestamp = @AnalyticsLatestSourceTimestamp,
AnalyticsSource NVARCHAR(100), AllOwnerIds NVARCHAR(MAX), AllAccessibleTeamIds NVARCHAR(MAX),
AllTeamIds NVARCHAR(MAX), AttributedTeamIds NVARCHAR(MAX), OwningTeams NVARCHAR(MAX),
...
FinexaLink NVARCHAR(MAX),
UpdatedAt = @UpdatedAt, RetrievedAt = @RetrievedAt, Archived = @Archived
```

Fourteen lines of `CREATE TABLE` column definitions were pasted into an `UPDATE SET` list. This is
invalid T-SQL. `SaveDealsAsync` cannot succeed under any input.

Confirmed present in `git show HEAD:` (commit `0aadb5f`), not a stale working copy.

### Fault B -- the exception is swallowed

Same file, lines 492-497:

```csharp
catch (Exception ex)
{
    _logger.LogError(ex, "Error saving deals to SQL database");
    _logger.LogError("DO NOT THROW EXCEPTION FOR NOW");
    //throw;
}
```

The other four save methods (`companies`, `contacts`, `tickets`, `users`, and
`InitializeDatabaseAsync`) all rethrow. Only deals swallows. A temporary workaround was committed.

### Fault C -- the orchestrator reports the retrieved count as the saved count

`Services/HubSpotSyncOrchestrationService.cs` returns `Success = true` with
`DealsProcessed = deals.Count` (line 101) -- the number fetched from HubSpot, not the number
written. Because Fault B suppresses the error, the sync completes normally.

### Net effect

The deals table receives nothing. The log contains one error line among many. The sync result says
success with a plausible deal count. Nobody finds out until someone queries the table.

### Fix

1. Replace lines 432-445 with proper `Column = @Parameter` assignments, and remove the columns
   that have no matching `DbModel` property.
2. Restore `throw;`.
3. Report the value returned by `ExecuteAsync` as the processed count, not the input count.
4. Verify with the check scripts, then run one real sync and query the table.

### Detection

```powershell
.\scripts\Check-SqlDdlInDml.ps1 -Path "<repo>"
```

Flags exactly those 14 lines. All other repos in the estate are clean.

## 2. Drive sales contracts lose dealer attribution on the way to SQL

**Severity: medium.**

`DriveFunctions/Models/SalesContractEntity.cs` declares and populates:

```csharp
public string? ForhandlerNavn { get; set; }    // line 28,  set from driveOrder.DealerName  (line 575)
public int? ForhandlerNummer { get; set; }     // line 32,  set from driveOrder.DealerNumber (line 576)
```

Neither appears in `MergeSalesContractSql`, and neither has a column in
`Services/SalesContractsSqlInitializer.cs`. The dealer name and number arrive on request headers
(`Forhandler`, `ForhandlerNummer`, configured in `infra/main.bicep` lines 19-22), are written to
Table Storage, and are absent from the SQL copy.

This is the "model property never passed to SQL" signature. Whether it is intentional is a
business question -- but it is undocumented, so it reads as an oversight.

### Detection

```powershell
.\scripts\Check-SqlParameterAlignment.ps1 `
    -ServiceFile "DriveFunctions\Services\DriveTableStorageService.cs" `
    -ModelFile   "DriveFunctions\Models\SalesContractEntity.cs", `
                 "DriveFunctions\Models\AdInventoryEntity.cs", `
                 "DriveFunctions\Models\AdPriceHistoryEntity.cs", `
                 "DriveFunctions\Models\AdEquipmentPackageEntity.cs"
```

## 3. HubSpot's update script is not re-runnable

**Severity: low, but it blocks incident response.**

`sql/02_Update_Tables.sql` uses bare `ALTER TABLE ... ADD` with no `sys.columns` guard, so it fails
on a second run. `sql/README.md` presents this as intentional. See
[schema-scripts.md](schema-scripts.md) for the guarded form.

The same script still adds `AnalyticsSourceData1` / `AnalyticsSourceData2` (lines 40-41) -- the
exact columns `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md` identifies as wrongly named and removes from
the C# side. The C# and the SQL disagree about which name is correct.

## 4. Money stored as `decimal` on table entities

**Severity: medium.** 50 properties across three files. Table Storage has no decimal type and does
not report the problem. Full measurement and remedy in [type-mapping.md](type-mapping.md).

## What these have in common

Every one compiles cleanly, and three of the four produce no error at runtime either. The build
signal and the log signal are both green. That is the reason this skill exists, and the reason
rule 1 is what it is.
