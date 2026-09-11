# Key design

## The catalogue

Every table in the estate, with its actual key pair. Use it to pick a precedent rather than
inventing a scheme.

| Table | PartitionKey | RowKey | Source |
|---|---|---|---|
| Echoes odometer readings | reading date `yyyy-MM-dd` | Echoes asset id | `Entities/OdometerReadingEntity.cs` |
| Echoes vehicle state | constant `"Vehicle"` | VIN (upper-cased) | `Entities/VehicleStateEntity.cs` |
| Easypark parking transactions | `StartDate` as `yyyy-MM-dd` | `ParkingId` | `Services/Storage/ParkingTransactionStorageService.cs:38` |
| Easypark operator lookup | constant `"Operator"` | operator name, lower-cased | same file, line 77 |
| Easypark billing records | invoice `fromDate` as `yyyy-MM-dd` | `InfoRecordId` | `Services/Storage/BillingRecordStorageService.cs:37,61` |
| Easypark billing companies | constant `"Company"` | `BaId` | same file, line 146 |
| Easypark fleet cars | constant `"Fleet"` | licence number | `Services/Storage/FleetCarStorageService.cs:19` |
| Easypark billing account cars | billing account id | licence number | `Services/Storage/BillingAccountFleetStorageService.cs:43` |
| Easypark last run state | constant `"State"` | constant `"LastRun"` | `Services/Storage/LastRunStateService.cs:18` |
| Easypark invoice period state | constant `"State"` | constant `"InvoicePeriodSync"` | `Services/Storage/InvoicePeriodSyncStateService.cs:24` |
| HubSpot companies/contacts/deals/tickets/users | constant per type (`"Company"`, ...) | HubSpot object id | `Models/TableEntities.cs:11` |

## Three shapes, and when each applies

### 1. Date partition, entity row -- time-series records

```csharp
PartitionKey = reading.Date.ToString("yyyy-MM-dd");
RowKey       = assetId;
```

Use for records that arrive continuously and are read by day or range. Echoes odometer readings,
Easypark parking transactions and billing records all use it.

- Repeat runs for the same day replace rather than accumulate -- the idempotency comes free.
- A day is a natural transaction boundary and stays well under the 100-operation limit for these
  volumes.
- Range queries scan a bounded set of partitions.
- Watch the hot-partition risk: today's partition takes every write. Acceptable at this estate's
  volumes; revisit if a single day exceeds a few thousand rows per second.

### 2. Constant partition, entity row -- lookup and desired-state tables

```csharp
public const string Partition = "Vehicle";
PartitionKey = Partition;
RowKey       = vin.ToUpperInvariant();
```

Use when the table is a modest set of current-state records read by id or scanned whole. Echoes
vehicle state, Easypark fleet cars and operator lookup, all HubSpot object tables.

- `GetEntityIfExistsAsync(Partition, id)` is a point read.
- `QueryAsync(e => e.PartitionKey == Partition)` scans one partition.
- Expose the constant as `public const string Partition` on the entity, as Echoes does, so callers
  cannot mistype it.
- Only appropriate while the table stays small; a single partition is a single scaling unit.

### 3. Constant partition, constant row -- singleton state

```csharp
private const string PartitionKey = "State";
private const string RowKey = "LastRun";
```

One row holding sync watermark state. Easypark's `LastRunStateService` and
`InvoicePeriodSyncStateService` share the table `EasyparkLastRunState` and separate by row key.
That is the right call -- one table, one row per concern.

Read it with a 404 guard, because the first run has no row:

```csharp
catch (RequestFailedException ex) when (ex.Status == 404)
{
    return null;   // no previous run
}
```

## Rules for choosing

1. **Start from the read.** If you will ask "everything for day X", the day is the partition. If you
   will ask "the record for id Y", id is the row key and the partition is a constant.
2. **The pair must be unique and stable.** A key derived from mutable data creates an orphan row
   when the data changes. Prefer the upstream id.
3. **The pair must be reproducible from the source record**, or the next sync inserts a duplicate
   instead of replacing.
4. **Normalise casing.** Row keys are case-sensitive. Pick a direction and apply it on read *and*
   write. Echoes upper-cases VINs (`VehicleStateService.cs:49,56`); Easypark lower-cases operator
   names and upper-cases licence plates (`NormalizeLicense`). Either is fine; inconsistency is not.
5. **Keys are strings.** Numeric ids need `.ToString()`, and sort lexicographically -- so `"10"`
   sorts before `"9"`. Zero-pad if you need ordering.
6. **Illegal characters.** `/ \ # ?`, control characters, and tab/newline are not allowed in either
   key. VINs, licence plates and numeric ids are safe; free text is not.

## Denormalised join keys

Table Storage has no joins, so the join key is copied onto the row at write time.

`OdometerReadingEntity.AccountNumber` carries the core-system account number ("Kontonr") mapped in
from the vehicle state table, so the downstream KM calculation reads one table instead of two.
`ParkingRowEntity` similarly carries the resolved `OperatorId` alongside the operator name.

Accept the duplication; it is the point. But resolve the value at write time and record where it
came from in the entity's doc comment, so a later reader knows which table is authoritative.
