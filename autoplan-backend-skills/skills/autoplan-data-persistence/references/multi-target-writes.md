# Multi-target writes

Several integrations write the same retrieved data to more than one store: Table Storage for fast
lookup, SQL for reporting, blob for the raw payload.

## Ordering and isolation

`HubSpotDataRetriever/Services/HubSpotSyncOrchestrationService.cs` writes all five object types to
Table Storage, then all five to SQL, sequentially:

```csharp
if (companies.Count > 0)
{
    var companyEntities = companies.Select(MappingService.ToTableEntity).ToList();
    await _tableStorageService.SaveCompaniesAsync(companyEntities, cancellationToken);
}
// ... contacts, deals, tickets, users
// then the same five again against _sqlDatabaseService
```

Two things this gets right:

- **Cheapest, most reliable target first.** Table Storage before SQL, so a SQL outage still leaves
  the fast-lookup copy current.
- **`Count > 0` guards.** No empty round-trips.

One thing it gets wrong, and it matters: **a failure in the middle of the sequence leaves the
targets inconsistent, and nothing reports it.** In HubSpot's case `SaveDealsAsync` swallows its
exception entirely and the orchestrator still returns `Success = true` with a deal count -- see the
`autoplan-sql-model-alignment` skill's `known-defects.md`. The pattern to avoid is not "sequential
writes"; it is *sequential writes whose outcome is not aggregated*.

### Do this instead

Isolate per target, collect outcomes, and report them:

```csharp
var results = new List<(string Target, int Written, Exception? Error)>();

foreach (var (name, write) in targets)
{
    try
    {
        var written = await write(cancellationToken);
        results.Add((name, written, null));
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Target {Target} failed", name);
        results.Add((name, 0, ex));
    }
}

var failed = results.Where(r => r.Error is not null).ToList();
return new SyncResult
{
    Success = failed.Count == 0,
    Message = failed.Count == 0 ? "Sync completed" : $"{failed.Count} target(s) failed",
    // counts are what was WRITTEN, never what was retrieved
};
```

Rules:

1. **A partial failure is not a success.** If any target failed, `Success` is false.
2. **Report written counts, not input counts.** Reporting `deals.Count` when zero deals were saved
   is how a broken sync stays invisible for months.
3. **Never swallow silently.** If a target must not abort the run, catch it -- and record it in the
   result. `//throw;` with a note is a committed outage.

## Blob archival of raw payloads

Only `DriveFunctions` does this today. `Services/DriveTableStorageService.cs`:

```csharp
_blobContainerClient = new BlobContainerClient(connectionString, "drivecontracts");

public async Task StoreDriveOrderJsonAsync(string id, string jsonPayload)
{
    await _blobContainerClient.CreateIfNotExistsAsync();
    var blobName = $"{id}.json";
    var blobClient = _blobContainerClient.GetBlobClient(blobName);
    using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(jsonPayload));
    await blobClient.UploadAsync(stream, overwrite: true);
    _logger.LogInformation("Drive order JSON stored in blob with Id: {Id}", id);
}
```

A second container, `adinventory`, stores periodic snapshots (line 475):

```csharp
var container = new BlobContainerClient(_storageConnectionString, "adinventory");
await container.CreateIfNotExistsAsync();
var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss");
var blobName = $"{branchId}_inventory_{timestamp}.json";
```

Conventions:

- **Name a per-record blob after the source id** (`{id}.json`), so a payload is retrievable from the
  record id alone. **Name a snapshot `{scope}_{what}_{yyyyMMddHHmmss}.json`**, which groups by scope
  and sorts chronologically within it -- a sortable timestamp format is what makes that work.
- **`overwrite: true`.** Same idempotency argument as table upserts.
- **One container per payload type**, named for the payload.
- **Archive before mapping.** The point is to replay a payload after finding a mapping bug; a
  payload archived after successful mapping cannot help you.
- **Hold the container client as a field.** `StoreDriveOrderJsonAsync` does;
  `StoreAdInventoryJsonAsync` constructs a new one per call. Prefer the field.

Echoes takes the lighter option instead -- `RawPayloadJson` as a property on the table entity. That
is fine while rows are small. Move to blob when payloads are large, numerous, or you want a
lifecycle policy to age them out.

### What is missing

No integration currently has a **replay path** -- nothing reads these blobs back. The archive is
insurance that has never been tested. If you add archival, add the reader at the same time and run
it once, or you have a container full of unusable JSON.

## Cross-store consistency

There are no distributed transactions here and none are wanted. Instead:

- Make every write idempotent, so re-running the sync converges the stores.
- Keep a watermark (Easypark's `LastRunStateService`) that only advances when **all** targets
  succeeded. Advancing it on partial success is how records get skipped permanently.
- Prefer re-processing a window to tracking per-record state. These syncs are small and upserts are
  cheap.
