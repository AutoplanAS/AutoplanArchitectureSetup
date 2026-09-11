---
name: autoplan-sql-model-alignment
description: "Keep the API type -> table entity -> DB model -> SQL column chain aligned in Autoplan integrations. Covers MERGE parameter binding, the C#/SQL/Table-Storage type mapping rules, idempotent schema scripts, and the runtime failures that a successful build does not catch. WHEN: \"write a MERGE statement\", \"save to SQL\", \"Must declare the scalar variable\", \"SQL parameter mismatch\", \"add a property to the DB model\", \"add a column\", \"create the table script\", \"map API response to database\", \"DbModel\", \"Dapper upsert\", \"why isn't this field being saved\", \"schema migration script\", \"decimal in table storage\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: DriveFunctions (SQL), HubSpotDataRetriever (cautionary)
---

# Autoplan SQL and Model Alignment

The most expensive class of defect in this codebase. HubSpot spent six documents on it and still
ships a broken statement today.

**The core problem: SQL lives in C# strings, so the compiler validates none of it.** Every HubSpot
post-mortem ends with "Build: Successful, Errors: 0" while the statement it describes cannot execute.
A green build is not evidence that persistence works.

## Rules

1. **A green build proves nothing here.** Never report SQL work as done on the strength of a compile. It must be executed against a database, or checked with the scripts below.
2. **The MERGE parameter list is a contract with the model class.** Every `@Name` must be a property on the type you bind. Dapper resolves them by reflection at runtime; a missing property throws `Must declare the scalar variable "@Name"`.
3. **Never paste DDL into DML.** Column definitions (`Name NVARCHAR(100)`) belong in `CREATE TABLE`. Inside an `UPDATE SET` list they are a syntax error. This is the live HubSpot bug -- see [known-defects.md](references/known-defects.md).
4. **Adding a property means four edits, not one.** Model, MERGE update list, MERGE insert list, and the schema script. Miss one and the field is silently never saved.
5. **Money is `decimal` in C# and `DECIMAL(18,2)` in SQL -- and neither in Table Storage.** Table Storage has no decimal type; see [type-mapping.md](references/type-mapping.md) for what it silently does instead.
6. **A model property with no SQL parameter is a silent data-loss bug.** It compiles, it maps, it is never persisted. Check both directions.

## Verifying alignment

Two scripts in `scripts/`, both validated against this estate:

```powershell
# Every @parameter resolves to a model property (and reports the count both ways).
.\scripts\Check-SqlParameterAlignment.ps1 `
    -ServiceFile <path>\SqlDatabaseService.cs `
    -ModelFile   <path>\DbModels.cs

# No DDL column definitions have leaked into a MERGE/UPDATE/INSERT.
.\scripts\Check-SqlDdlInDml.ps1 -Path <repo-or-file>
```

Measured 2026-08-19: HubSpot passes the first (212 parameters, 212 properties) and fails the second
with 14 lines. All other repos pass both. Run both before any SQL change is called done.

## The four-layer chain

```
API JSON  ->  Types.cs  ->  TableEntity  ->  DbModel  ->  SQL columns
                          (hot subset)     (full record)
```

Layers deliberately differ in width -- the table entity is a hot subset, the DB model is the full
record. That is by design, but it means a property can exist at one layer and not the next, which is
exactly how fields go missing. See [three-layer-model.md](references/three-layer-model.md).

## References

- [three-layer-model.md](references/three-layer-model.md) -- what each layer is for, what may drop between them, and how to add a field end to end.
- [merge-contract.md](references/merge-contract.md) -- the MERGE shape used here, Dapper vs explicit `SqlCommand` binding, and null handling.
- [type-mapping.md](references/type-mapping.md) -- C# / SQL Server / Table Storage type table, including the measured behaviour of `decimal` in Table Storage.
- [schema-scripts.md](references/schema-scripts.md) -- idempotent create scripts, additive migrations, and post-deploy verification queries.
- [known-defects.md](references/known-defects.md) -- the live defects in this estate, with file and line, and what each one teaches.
