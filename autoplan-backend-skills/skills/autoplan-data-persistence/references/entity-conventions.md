# Entity conventions

## The shape

```csharp
using Azure;
using Azure.Data.Tables;

namespace EchoesIntegration.Entities;

/// <summary>
/// A retrieved odometer reading.
/// PartitionKey = date (yyyy-MM-dd), RowKey = Echoes asset id.
/// </summary>
public class OdometerReadingEntity : ITableEntity
{
    public string PartitionKey { get; set; } = string.Empty;
    public string RowKey { get; set; } = string.Empty;
    public DateTimeOffset? Timestamp { get; set; }
    public ETag ETag { get; set; }

    public string? Vin { get; set; }
    public long Odometer { get; set; }
    public double OdometerKm { get; set; }

    /// <summary>Idempotency key ("{assetId}-{readingEpochMs}").</summary>
    public string? SourceReadingId { get; set; }

    /// <summary>Timestamp of the reading reported by Echoes (UTC).</summary>
    public DateTimeOffset? ReadingDateTime { get; set; }

    /// <summary>When this row was retrieved from the API (UTC).</summary>
    public DateTimeOffset RetrievedAt { get; set; }

    /// <summary>Raw report row as JSON.</summary>
    public string? RawPayloadJson { get; set; }
}
```

Conventions:

- **Implement `ITableEntity` directly.** Not `TableEntity`, not `ITableEntity<T>`. All four
  interface members are declared explicitly, in the same order, at the top.
- **The class doc comment states the key pair.** This is the single most useful line in the file --
  it is otherwise invisible until you read the service that writes it.
- **`Timestamp` and `ETag` are the service's, not yours.** Never set them. `Timestamp` is the row's
  last-modified time as recorded by Azure, which is *not* the same as when the record happened
  upstream -- carry your own field for that.
- **Suffix the class `Entity`** and keep it in `Entities/` (Echoes, Easypark) or `Models/`
  (Drive, HubSpot). Match whichever the repo already uses.
- **Expose a constant partition as `public const string Partition`** when the partition is fixed.

## Supported property types

Table Storage stores these EDM types only:

| EDM | C# |
|---|---|
| `Edm.String` | `string` |
| `Edm.Int32` | `int` |
| `Edm.Int64` | `long` |
| `Edm.Double` | `double` |
| `Edm.Boolean` | `bool` |
| `Edm.DateTime` | `DateTime`, `DateTimeOffset` |
| `Edm.Guid` | `Guid` |
| `Edm.Binary` | `byte[]` |

Nullable variants of these are fine.

**Anything else is a problem, and `decimal` is a silent one.** The SDK writes a `decimal` as a bare
JSON number with no `@odata.type` annotation, so the stored column type is inferred from the value.
No exception is thrown. Measured and documented in the `autoplan-sql-model-alignment` skill's
`type-mapping.md`. Convert explicitly at the boundary:

```csharp
Price = (double)transaction.Price,   // EasyparkIntegration ParkingTransactionStorageService.cs:44
```

Enums, nested objects and collections are not supported either. Serialise to JSON in a `string`
property, or flatten to scalar columns.

Other limits worth knowing: 255 properties per entity (including the three system ones), 1 MB per
entity, 64 KB per string property.

## Audit and idempotency fields

Carry these on records retrieved from an upstream API:

| Field | Type | Purpose |
|---|---|---|
| `RetrievedAt` | `DateTimeOffset` | When this row was fetched. Distinguishes data freshness from row modification. |
| `<Event>DateTime` | `DateTimeOffset?` | When the event happened upstream. Never conflate with `Timestamp`. |
| `SourceReadingId` / source id | `string?` | Upstream idempotency key, e.g. `"{assetId}-{epochMs}"`. |
| `RawPayloadJson` | `string?` | The source row as JSON, for replay and for diagnosing a mapping bug after the fact. |

HubSpot's entities add `CreatedAt`, `UpdatedAt`, `RetrievedAt` and `Archived` -- the same idea with
a soft-delete flag.

`RawPayloadJson` is cheap insurance while a payload is small. If payloads are large or numerous,
archive to blob instead -- see [multi-target-writes.md](multi-target-writes.md).

## Time

- Store `DateTimeOffset`, in UTC, always.
- Never write `DateTime.Now`. Use `DateTime.UtcNow` or `DateTimeOffset.UtcNow`.
- Convert at the boundary and keep it converted. Easypark's `ParkingTransactionEntity` stores
  `DateTime StartDate` -- workable only because the source is already normalised. Prefer
  `DateTimeOffset` in new entities.

## Constructing entities

Keep mapping out of the storage service where the shape is non-trivial. Drive puts it in a
constructor on the entity (`new DriveOrderEntity(driveOrder)`); Easypark maps inline in the
service. Either is acceptable -- but pick one per repo, and note that inline mapping is where the
`(double)` casts hide, so make them conspicuous.
