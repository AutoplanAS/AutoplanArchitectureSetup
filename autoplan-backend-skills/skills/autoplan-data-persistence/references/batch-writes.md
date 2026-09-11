# Batch writes

## The two hard limits

A table transaction (`SubmitTransactionAsync`):

1. **Cannot span partitions.** Every action must share one `PartitionKey`.
2. **Holds at most 100 operations.**

Both are enforced by the service. Violating the first returns a `400` with
`CommandsInBatchActOnDifferentPartitions`; the second returns `InvalidInput`.

A transaction is also all-or-nothing: one bad entity fails the whole batch.

## The correct form -- group, then chunk

`EchoesIntegration/Services/OdometerStorageService.cs`:

```csharp
// Batch per partition key: a table transaction cannot span partitions and allows
// at most 100 operations, so readings are grouped by date and then chunked.
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
```

This is safe for any input. Copy it.

## The fragile form -- chunk only

Easypark has three helpers that chunk without grouping:

- `Services/Storage/BillingRecordStorageService.cs:285` -- generic `UpsertBatchAsync<T>`
- `Services/Storage/BillingAccountFleetStorageService.cs:78`
- `Services/Storage/FleetCarStorageService.cs:73` (manual `Skip`/`Take` rather than `Chunk`)

```csharp
foreach (var chunk in entities.Chunk(100))
{
    var batch = chunk.Select(e => new TableTransactionAction(TableTransactionActionType.UpsertReplace, e)).ToList();
    await tableClient.SubmitTransactionAsync(batch, cancellationToken);
}
```

**These are not currently broken.** Every caller happens to pass a single-partition set:
`BillingRecordStorageService` hoists `var partitionKey = fromDate.ToString("yyyy-MM-dd")` outside
the loop (lines 37 and 168), `FleetCarStorageService` uses the constant `"Fleet"`, and
`BillingAccountFleetStorageService` writes one billing account per call.

They are safe *by caller construction*, not by design -- and `UpsertBatchAsync<T>` is generic and
private, so the constraint is nowhere stated. The first caller that passes a mixed-partition list
gets a runtime 400. Add the `GroupBy` even when the current callers do not need it; it costs one
line and removes the constraint.

## Choosing batch or per-item

| | Transaction | Per-item upsert |
|---|---|---|
| Round trips | 1 per 100 | 1 per entity |
| Atomicity | all-or-nothing per batch | independent |
| One bad entity | fails the batch | fails only itself |
| Partition constraint | yes | no |

Use transactions for bulk sync writes -- that is nearly always the right answer.

Use per-item when entities span many partitions with few rows each, or when one poison record must
not block the rest. HubSpot's `Services/TableStorageService.cs` does per-item with a try/catch
around each write, so a single bad record is logged and skipped:

```csharp
foreach (var company in companies)
{
    try
    {
        await tableClient.UpsertEntityAsync(company, TableUpdateMode.Replace, cancellationToken);
        savedCount++;
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Error saving company {CompanyId} to table storage", company.RowKey);
    }
}
```

The isolation is right; the cost is one round-trip per entity, and the method is copy-pasted five
times in that file. If you need this, write it once as a generic helper.

## Update mode

Always `TableUpdateMode.Replace` (`UpsertReplace` in a transaction).

`Merge` keeps properties already on the stored row that are absent from the entity you send, which
means a removed field lingers forever. Replace makes the entity the whole truth. Every service in
the estate uses Replace.

## Table creation

`CreateIfNotExistsAsync` is a network call. Cache it per client instance:

```csharp
private bool _tableCreated;

private async Task EnsureTableAsync(CancellationToken ct)
{
    if (!_tableCreated)
    {
        await _table.CreateIfNotExistsAsync(ct);
        _tableCreated = true;
    }
}
```

Measured 2026-08-19: only Echoes does this. Easypark makes 20 unguarded calls, Drive 12, HubSpot 5
-- one extra round-trip on every write path. The flag is only useful if the service is registered
as a singleton, which is the house default.

The flag is not thread-safe, but the failure mode is a redundant idempotent call, not corruption.
That is an acceptable trade here; do not add a lock.
