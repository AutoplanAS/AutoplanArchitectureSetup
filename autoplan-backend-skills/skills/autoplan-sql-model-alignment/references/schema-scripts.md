# Schema scripts

## Two places schema is defined -- keep both

1. **Startup initializer** in C#, so a fresh environment works with no manual step.
2. **Checked-in `.sql` files**, so a DBA can review, and so production can be updated without a
   deployment.

Both exist today: `HubSpotDataRetriever` has `InitializeDatabaseAsync` *and* `sql/*.sql`;
`DriveFunctions` has `SalesContractsSqlInitializer`. They must be kept in step, and today they are
not -- see [known-defects.md](known-defects.md).

## Idempotent creation

Drive's initializer (`Services/SalesContractsSqlInitializer.cs`) is the pattern to copy:

```csharp
private const string CreateTableSql = @"IF OBJECT_ID('dbo.SalesContracts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SalesContracts
    (
        [Id] NVARCHAR(64) NOT NULL PRIMARY KEY,
        [SignertDato] DATETIME2 NULL,
        ...
    );
END";
```

- `IF OBJECT_ID(...) IS NULL` -- safe to run on every start.
- Bracketed identifiers -- required here because column names contain Norwegian characters.
- Runs as an `IHostedService`, so the table exists before the first trigger fires.
- Gated by a configuration flag (`_enableSchemaInitialization`), so production can turn it off and
  apply schema through a reviewed script instead. Keep the flag; do not let a function app hold
  DDL rights in production by default.

HubSpot's equivalent uses `IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'X')`, which is
equally fine.

## Additive migration

Adding a column must never rewrite the table.

```sql
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.HubSpotDeals') AND name = 'NewColumn')
BEGIN
    ALTER TABLE dbo.HubSpotDeals ADD NewColumn NVARCHAR(255) NULL;
END
```

`ALTER TABLE ... ADD` with `NULL` is a metadata-only change: no data is touched and no default is
backfilled.

**Always guard with the `sys.columns` check.** HubSpot's `sql/02_Update_Tables.sql` does not:

```sql
ALTER TABLE HubSpotCompanies ADD TotalRevenue INT NULL;
ALTER TABLE HubSpotCompanies ADD TimeZone NVARCHAR(50) NULL;
```

Its own README rationalises this as deliberate -- "The update script does NOT include existence
checks. If you run it twice, you'll get errors. This is intentional for safety." It is not safety.
It makes the script unrunnable in any environment whose state you are unsure of, which is exactly
when you need to run it. Guard the statements; re-runnability is the safety property.

## Numbered, ordered, forward-only

```
sql/
  01_Initialize_Tables.sql   -- full schema, idempotent, safe on a fresh database
  02_Update_Tables.sql       -- additive changes since 01
  03_...                     -- next change set
```

Never edit a script that has run in production. Add the next number.

## Post-deploy verification

Run these after any schema change, before declaring it done.

```sql
-- Columns the model expects but the table lacks.
SELECT name, system_type_id, is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.HubSpotDeals')
ORDER BY name;

-- Row count and freshness, to confirm the sync is actually writing.
SELECT COUNT(*) AS Rows, MAX(RetrievedAt) AS LastWrite FROM dbo.HubSpotDeals;

-- Columns that are always NULL: mapping never populated them.
SELECT COUNT(*) AS Total, COUNT(NewColumn) AS Populated FROM dbo.HubSpotDeals;
```

The third query is the one that catches the silent failure. A column with `Populated = 0` after a
sync means the MERGE or the mapping was missed -- the deployment succeeded and the data is not
there.

## Executing scripts

```powershell
sqlcmd -S <server> -d <database> -i sql\02_Update_Tables.sql
```

Back up production before running a change set. HubSpot's `sql/README.md` documents the
environment order -- dev runs both scripts, staging and production run only the update script.
