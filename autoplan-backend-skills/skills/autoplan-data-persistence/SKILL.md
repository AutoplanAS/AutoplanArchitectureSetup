---
name: autoplan-data-persistence
description: "Azure Table Storage and Blob persistence for Autoplan integrations: partition and row key design, ITableEntity conventions and type limits, transactional batch upserts, multi-target write orchestration with error isolation, blob archival of raw payloads, and keyed DI for multi-account storage. WHEN: \"store this in table storage\", \"create a table entity\", \"partition key\", \"row key\", \"batch upsert\", \"SubmitTransactionAsync\", \"save to blob\", \"archive the raw payload\", \"query table storage\", \"TableServiceClient\", \"multiple storage accounts\", \"state table\", \"last run timestamp\", \"idempotent writes\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration
---

# Autoplan Data Persistence

Azure Table Storage is the default store for integration state and retrieved records. SQL is the
reporting target (see `autoplan-sql-model-alignment`); blobs hold raw payloads for replay.

Reference: `EchoesIntegration/Services/OdometerStorageService.cs` and `VehicleStateService.cs`.
They are short, and everything below is visible in them.

## Rules

1. **Writes are idempotent upserts, never inserts.** Every sync re-runs. Choose keys so a repeat run
   replaces the previous row instead of duplicating it: `TableUpdateMode.Replace`.
2. **The key pair is the data model.** Table Storage gives you exactly one efficient query --
   partition + row. Decide keys from how you will read, not from what the record contains. See
   [key-design.md](references/key-design.md).
3. **A transaction cannot span partitions and holds at most 100 operations.** Group by partition
   key *then* chunk. Chunking alone is a latent bug -- see [batch-writes.md](references/batch-writes.md).
4. **Normalise key casing at the boundary.** Row keys are case-sensitive, so `ABC123` and `abc123`
   are two rows. Echoes upper-cases VINs on both read and write.
5. **Cache `CreateIfNotExistsAsync`.** It is a network round-trip. Call it once per client instance,
   not once per write. Only Echoes does this today; the estate makes 37 unguarded calls.
6. **Timestamps are UTC `DateTimeOffset`.** Never a local `DateTime`.
7. **No `decimal` on an `ITableEntity`.** Table Storage has no decimal EDM type. The write succeeds
   with no exception, but the SDK sends the value without a type annotation, so the stored column
   type is inferred from the value. Convert to `double` at the boundary, explicitly. Measured
   evidence in `autoplan-sql-model-alignment`'s `type-mapping.md`.

## The shape

```csharp
public class TableOdometerStorageService(
    TableServiceClient tableServiceClient,
    IOptions<EchoesOptions> options) : IOdometerStorageService
{
    private readonly TableClient _table =
        tableServiceClient.GetTableClient(options.Value.OdometerTableName);
    private bool _tableCreated;

    public async Task StoreReadingsAsync(IEnumerable<OdometerReadingEntity> readings, CancellationToken ct = default)
    {
        if (!_tableCreated)
        {
            await _table.CreateIfNotExistsAsync(ct);
            _tableCreated = true;
        }

        foreach (var partitionGroup in readings.GroupBy(r => r.PartitionKey))
        {
            foreach (var chunk in partitionGroup.Chunk(100))
            {
                var batch = chunk
                    .Select(r => new TableTransactionAction(TableTransactionActionType.UpsertReplace, r))
                    .ToList();
                await _table.SubmitTransactionAsync(batch, ct);
            }
        }
    }
}
```

Table name from options, not a constant. An interface per store. Registered
`AddSingleton<IOdometerStorageService, TableOdometerStorageService>()`, so the cached
`_tableCreated` flag survives for the process lifetime.

## References

- [key-design.md](references/key-design.md) -- the partition and row key catalogue from every table in the estate, and how to choose.
- [entity-conventions.md](references/entity-conventions.md) -- `ITableEntity` shape, supported types, audit and idempotency fields.
- [batch-writes.md](references/batch-writes.md) -- transaction limits, the group-then-chunk rule, and per-item fallback.
- [multi-target-writes.md](references/multi-target-writes.md) -- writing to table + SQL + blob, error isolation, and blob archival for replay.
- [storage-clients.md](references/storage-clients.md) -- DI registration, keyed clients for multiple accounts, connection string configuration.
- [gaps.md](references/gaps.md) -- what this estate does *not* handle, so you do not assume it does.
