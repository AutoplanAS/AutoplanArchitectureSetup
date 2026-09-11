# The MERGE contract

## The house statement shape

Every SQL upsert in this estate is a single-row `MERGE` keyed on the primary key:

```sql
MERGE INTO <Table> AS target
USING (SELECT @Id AS Id) AS source
ON target.Id = source.Id
WHEN MATCHED THEN
    UPDATE SET Col1 = @Col1, Col2 = @Col2, ...
WHEN NOT MATCHED THEN
    INSERT (Id, Col1, Col2, ...)
    VALUES (@Id, @Col1, @Col2, ...);
```

Used by `HubSpotDataRetriever/Services/SqlDatabaseService.cs` and
`DriveFunctions/Services/DriveTableStorageService.cs` (`MergeSalesContractSql`,
`MergeAdInventorySql`).

Three lists must stay in step: the `UPDATE SET` assignments, the `INSERT` column list, and the
`VALUES` parameter list. Editing one or two of the three is the single most common mistake.

> `MERGE` has known concurrency caveats in SQL Server. It is safe here because these are
> single-key, single-writer timer syncs. Do not carry the pattern into a concurrent writer without
> revisiting it.

## Two binding styles, both in use

### Dapper -- concise, reflection-bound (HubSpot)

```csharp
var savedCount = await connection.ExecuteAsync(sql, companies);
```

Passing an `IEnumerable` makes Dapper execute the command **once per element**, resolving each
`@Name` against a property of the element type by reflection.

- Adding a property to the model is enough for it to be bindable.
- A `@Name` with no matching property is **not** a compile error. SQL Server receives an
  unparameterised variable and returns `Must declare the scalar variable "@Name"`.
- Nothing warns you about a property that no statement uses.

### Explicit SqlCommand -- verbose, hand-bound (Drive)

```csharp
await using var command = new SqlCommand(MergeSalesContractSql, connection);
AddParameter(command, "@Id", salesContractEntity.Id);
AddParameter(command, "@SignertDato", salesContractEntity.SignertDato);
// ... one call per parameter
```

`DriveTableStorageService.AddParameter` (line 320) is the null-and-type helper:

```csharp
private static void AddParameter(SqlCommand command, string name, object? value)
{
    var parameter = new SqlParameter(name, DBNull.Value);
    if (value is null) { command.Parameters.Add(parameter); return; }

    switch (value)
    {
        case string s:
            parameter.SqlDbType = SqlDbType.NVarChar;
            parameter.Size = s.Length > 4000 ? -1 : Math.Max(1, s.Length);  // -1 => NVARCHAR(MAX)
            parameter.Value = s;
            break;
        case int:      parameter.SqlDbType = SqlDbType.Int; parameter.Value = value; break;
        case bool:     parameter.SqlDbType = SqlDbType.Bit; parameter.Value = value; break;
        case DateTime: parameter.SqlDbType = SqlDbType.DateTime2; parameter.Value = value; break;
        case decimal:
            parameter.SqlDbType = SqlDbType.Decimal;
            parameter.Precision = 18;
            parameter.Scale = 2;                 // matches DECIMAL(18,2); rounds beyond 2 places
            parameter.Value = value;
            break;
        default: parameter.Value = value; break;
    }

    command.Parameters.Add(parameter);
}
```

Two things this gets right that are easy to lose:

- **`DBNull.Value`, not `null`.** A C# `null` passed as a parameter value is not a SQL `NULL`;
  it leaves the parameter unset. The helper defaults every parameter to `DBNull.Value` first.
- **Explicit `SqlDbType`.** Without it ADO.NET infers a type per call, so the same column can be
  sent as different types on different rows, which defeats plan reuse and can cause implicit
  conversions.

Note `DateTimeOffset` falls through to `default`. Drive converts explicitly at the call site
(`entity.UpdatedAt?.UtcDateTime`) rather than relying on inference -- keep doing that.

### Which to use

Prefer Dapper for wide models bound to one type. Prefer explicit binding when values need
conversion on the way in (Drive's `.UtcDateTime`, precision pinning) or when one method writes
several tables. Do not mix styles within one statement.

## Verifying the contract

```powershell
.\scripts\Check-SqlParameterAlignment.ps1 -ServiceFile <service>.cs -ModelFile <model>.cs[,<model2>.cs]
```

Reports both directions:

- **Parameters with no model property** -- will throw at runtime.
- **Model properties never passed to SQL** -- silent data loss.

**Pass every model the file binds to.** A service with several statements binds several types;
supplying only one produces a long list of spurious "missing" parameters. `DriveTableStorageService`
binds four (`SalesContractEntity`, `AdInventoryEntity`, `AdPriceHistoryEntity`,
`AdEquipmentPackageEntity`).

Verified 2026-08-19: HubSpot 212/212 clean; Drive clean on parameters with two genuine
never-persisted properties (see [known-defects.md](known-defects.md)).

## Null semantics

- Model properties are nullable wherever the API may omit the value -- which is nearly everywhere.
- SQL columns are `NULL` except the identity and audit columns (`Id`, `CreatedAt`, `UpdatedAt`,
  `RetrievedAt`, `Archived`).
- A `MERGE` always writes every column in its list. A property that is `null` because mapping was
  never wired **overwrites a previously good value with `NULL`** on the next sync. Missing mapping
  is therefore destructive, not merely incomplete.
