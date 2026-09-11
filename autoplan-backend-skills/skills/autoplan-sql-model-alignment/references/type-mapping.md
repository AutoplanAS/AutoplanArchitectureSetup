# Type mapping

## C# -> SQL Server

The house conventions, taken from `HubSpotDataRetriever/Services/SqlDatabaseService.cs`,
`sql/01_Initialize_Tables.sql` and `DriveFunctions/Services/SalesContractsSqlInitializer.cs`.

| Meaning | C# | SQL Server |
|---|---|---|
| Money, revenue, prices | `decimal?` | `DECIMAL(18,2)` |
| Percentage, probability | `decimal?` | `DECIMAL(5,2)` |
| Score, average, duration | `decimal?` | `DECIMAL(10,2)` |
| Exchange rate | `decimal?` | `DECIMAL(10,6)` |
| Count, year, small number | `int?` | `INT` |
| Organisation number, epoch ms | `long?` | `BIGINT` |
| Boolean flag | `bool?` | `BIT` |
| Timestamp | `DateTimeOffset?` | `DATETIMEOFFSET` (HubSpot) or `DATETIME2` (Drive) |
| Id, code, short text | `string?` | `NVARCHAR(50)` |
| Name, title, category | `string?` | `NVARCHAR(100)` |
| URL, email | `string?` | `NVARCHAR(255)` |
| Address, description | `string?` | `NVARCHAR(500)` .. `NVARCHAR(MAX)` |
| Delimited id list | `string?` | `NVARCHAR(MAX)` |

Rules:

- **Money is never `float`/`double`/`REAL`.** Binary floating point cannot represent decimal
  fractions exactly.
- **Dates are timezone-aware.** `DATETIMEOFFSET` preserves the offset; `DATETIME2` does not.
  HubSpot standardised on `DATETIMEOFFSET`; Drive uses `DATETIME2` and converts to UTC at the
  binding site (`entity.UpdatedAt?.UtcDateTime`). Either is workable, but be explicit -- never
  hand a local `DateTime` to either.
- **Nullable wherever the API can omit the value.** Non-nullable only for the identity and audit
  columns.
- **Lists are delimited strings, not related tables.** `AllOwnerIds`, `AllTeamIds`,
  `AllAssociatedContactEmails` are `NVARCHAR(MAX)`. This is a deliberate trade for a sync target
  that is read by reporting tools, not a normalisation oversight.

## C# -> Azure Table Storage

Table Storage supports a fixed set of EDM types: `Edm.String`, `Edm.Binary`, `Edm.Boolean`,
`Edm.DateTime`, `Edm.Double`, `Edm.Guid`, `Edm.Int32`, `Edm.Int64`.

**`decimal` is not among them, and the SDK does not tell you.**

Measured against `Azure.Data.Tables` 12.9.1 by capturing the serialized request body:

| C# property | Value | Serialized payload |
|---|---|---|
| `double?` | `123.45` | `"AnnualRevenue":123.45,"AnnualRevenue@odata.type":"Edm.Double"` |
| `decimal?` | `123.45` | `"AnnualRevenue":123.45` |
| `decimal?` | `123` | `"AnnualRevenue":123` |
| `decimal?` | `decimal.MaxValue` | `"AnnualRevenue":79228162514264337593543950335` |

Every supported type is written with an explicit `@odata.type` annotation. `decimal` is written as
a **bare JSON number with no annotation**, so the service infers the column type from the literal:
an integral value looks like `Edm.Int32`, a fractional one like `Edm.Double`. The stored type
therefore depends on the value, and precision beyond `double` cannot survive.

No exception is thrown. The write succeeds.

### What to do instead

Convert at the boundary, as Easypark does in
`Services/Storage/ParkingTransactionStorageService.cs` (line 44):

```csharp
Price = (double)transaction.Price,
PriceVatAmount = (double)transaction.PriceVatAmount,
```

The entity property is `double`; the domain model keeps `decimal`. The cast is explicit and
visible. Echoes does the same for odometer values (`double OdometerKm`).

If exact decimal fidelity matters in the table, store the value as a `string` in invariant
culture and parse on read. Do not store money as `decimal` on an `ITableEntity` and assume it
round-trips.

### Current exposure

Measured 2026-08-19 -- `ITableEntity` classes containing `decimal` properties:

| File | Count |
|---|---|
| `HubSpotDataRetriever/Models/TableEntities.cs` | 25 |
| `DriveFunctions/Models/SalesContractEntity.cs` | 20 |
| `DriveFunctions/Models/DriveOrderEntity.cs` | 5 |

Easypark, Echoes, OFV and the Autoplan API have none. Note these are mostly monetary fields, and
that the SQL copy of the same data is `DECIMAL(18,2)` and therefore correct -- the exposure is in
the Table Storage copy.

## The three-way mismatch to watch

The same logical field is often three types at once:

```
API JSON string "123.45"  ->  decimal? (DbModel)   ->  DECIMAL(18,2)   [exact]
                          ->  double   (TableEntity) ->  Edm.Double     [approximate]
```

That is acceptable when Table Storage is the fast-lookup copy and SQL is the record. It is not
acceptable if the table copy feeds billing. Decide which store is authoritative and say so in the
entity's XML doc comment.
