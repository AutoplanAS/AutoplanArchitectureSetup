# Gaps

What the estate does **not** do. Each of these is a real absence, verified by search rather than
assumed -- so do not copy an existing storage service expecting to find it.

## 1. No throttling (429) handling anywhere in storage code

Table Storage returns `429 TooManyRequests` when a partition exceeds ~2,000 entities/second, and
`503` under storage-account pressure. **No storage service in any repo handles either.**

The only 429 handling that exists is in an HTTP client, against the HubSpot API:

- `HubSpotDataRetriever/Services/HubSpotClient.cs:44`

Storage-layer catch blocks handle exactly one status code -- `404`, for "state not written yet":

- `EasyparkIntegration/Services/Storage/LastRunStateService.cs:40`
- `EasyparkIntegration/Services/Storage/InvoicePeriodSyncStateService.cs:53`
- `SmartCarIntegration/.../SmartCarTableStorageService.cs:93`

Today's volumes make this mostly theoretical -- but a hot partition (see
[key-design.md](key-design.md)) plus a large backfill is exactly the combination that produces it,
and the current failure mode is an unhandled `RequestFailedException` that aborts the whole run
mid-batch, leaving targets inconsistent.

If you add handling, catch `RequestFailedException` with `Status` of 429 or 503 and retry with
exponential backoff plus jitter, honouring `Retry-After` when present.

## 2. No configured retry policy on storage clients

Every `TableServiceClient` and `TableClient` is constructed with a bare connection string:

```csharp
new TableServiceClient(dataStorageConnectionString)
```

The Azure SDK's default retry policy applies (a few exponential retries on transient failures),
which is why this mostly works. But it is the default, not a decision -- nobody has passed a
`TableClientOptions`, so the retry count, delay and timeout are whatever the SDK version ships. An
SDK upgrade changes them silently.

Where behaviour matters, be explicit:

```csharp
var options = new TableClientOptions();
options.Retry.MaxRetries = 5;
options.Retry.Mode = RetryMode.Exponential;
options.Retry.Delay = TimeSpan.FromSeconds(2);
new TableServiceClient(connectionString, options);
```

## 3. No reverse mapping

Mapping is one-way: source model to entity to SQL. **No `FromTableEntity`, no entity-to-domain
mapper exists anywhere.** Nothing reads a row back and reconstitutes a domain object.

Consequence: Table Storage here is a write-only sink queried by external consumers, not a
repository. Do not assume you can round-trip. If you need to read data back, you are writing the
first reader in the estate -- and you will discover which lossy conversions (`(double)` casts,
`decimal` precision, flattened JSON) actually matter.

## 4. No replay path for archived payloads

Drive archives raw JSON to the `drivecontracts` and `adinventory` blob containers
(`DriveTableStorageService.cs:152, 477`) and Echoes keeps `RawPayloadJson` on the entity. **Nothing
reads either back.** The archive has never been exercised.

If you rely on it for recovery, write and run the reader before you need it.

## 5. No lifecycle management

No retention policy, no archival tier, no cleanup, no `DeleteEntityAsync` on any data table. Every
table and container grows without bound. Fine at current volumes; state it explicitly when
designing a high-volume table, because the partition scheme you choose is what makes deletion cheap
or impossible later (date partitions can be dropped wholesale; entity-id partitions cannot).

## 6. No optimistic concurrency

`ETag` is declared on every entity because `ITableEntity` requires it, and it is **never used**.
Every write is an unconditional `UpsertReplace` -- last writer wins.

This is the right call for single-writer sync jobs, which is what these all are. It becomes wrong
the moment two writers touch the same row, or a read-modify-write appears. If you add either, pass
the `ETag` you read to the update and handle `412 Precondition Failed`.

## 7. No tests exercise the storage constraints

There is exactly one storage-service test file in the estate:
`EasyparkIntegration.Tests/Services/BillingRecordStorageServiceTests.cs`. It is a good file -- six
tests covering row expansion, field mapping and operator lookup -- but it builds the service from
`Mock<TableServiceClient>` and `Mock<TableClient>`, so it verifies **mapping**, not persistence.

That distinction is the point. A mock accepts a mixed-partition transaction, a 150-operation batch
and a `decimal` property without complaint. Every constraint in this skill is invisible to it.

No repo runs tests against Azurite or a real account. (Azurite appears in several READMEs as the
local *development* storage emulator -- it is not wired into any test project.)

Practical consequence: **nothing enforces these rules but review.** That is why the checker scripts
in `scripts/` exist, and why the entity and batch rules here are worth applying by hand.

## Priority

If you are picking one to fix: **429/503 handling with backoff** (1). It is the only gap whose
absence causes a run to fail outright rather than merely limit what you can do later.
