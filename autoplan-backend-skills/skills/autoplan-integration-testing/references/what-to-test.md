# What to test

Coverage percentage is not the target and nobody measures it. The target is: **the behaviours where
being wrong is expensive and reading the code does not tell you whether it is right.**

Echoes has 47 tests across 5 files and almost none of them assert a property mapping. That is the
model to copy.

## Naming

`Subject_Condition_ExpectedOutcome`, used consistently across all 47 Echoes tests:

```
GetVehicleByVin_NotFound_ReturnsNull
Handler_On401Twice_DoesNotRetryForever
RetrieveAll_ReportUnavailable_FallsBackToVehicleList
ActiveVehicle_NotInEchoes_IsCreated
```

A failure in the CI log then reads as a sentence and you know what broke without opening the file.

## The behaviours worth covering

### 1. Auth renewal and its termination

`EchoesAuthenticationTests.cs` -- 11 tests, the densest value in the estate.

| Test | Proves |
|---|---|
| `Provider_CreatesPrivacyKey_WhenNoneConfigured` | the create call is made, to the right URL, with the right body |
| `Provider_CachesCreatedKey_AndOnlyCallsApiOnce` | `Assert.Single(handler.Requests)` -- no per-call token fetch |
| `Provider_UsesConfiguredKey_WithoutCallingApi` | `Assert.Empty(handler.Requests)` -- config short-circuits |
| `Provider_AfterInvalidate_CreatesAFreshKey` | invalidation actually discards |
| `Provider_RenewsKeyThatExpiresWithinTheMargin` | the 7-day margin triggers before expiry, not after |
| `Handler_On401_RenewsKeyAndRetriesOnce` | the retry happens **and carries the new key** |
| `Handler_On401Twice_DoesNotRetryForever` | the loop terminates |

The last two are a pair. Write both or neither -- the first alone will still pass if you have
written an infinite retry.

Note how the retry test asserts on *headers*, not just the status code:

```csharp
Assert.Equal(2, inner.Requests.Count);
Assert.Equal(1, provider.InvalidateCount);
Assert.Equal("Privacykey stale", inner.Requests[0].Headers.GetValues("Authorization").Single());
Assert.Equal("Privacykey fresh", inner.Requests[1].Headers.GetValues("Authorization").Single());
```

A retry that resends the *stale* key would pass a status-code-only assertion on a fake that returns
200 second. This does not.

### 2. Pagination termination

`ListVehicles_FullPage_FetchesNextPage`. Use the sequence fake, whose last response repeats, so a
non-terminating loop fails on a count assertion rather than an exception.

Always assert the **number of requests**, not just the aggregated result. A loop that fetches page 1
twice produces the right item count in some shapes and the wrong request count in all of them.

### 3. Reconciliation, as a full matrix

`VehicleActivationSyncServiceTests.cs` covers desired-state x actual-state exhaustively:

| | In Echoes | Not in Echoes |
|---|---|---|
| **Active** | `AlreadyInEchoes_NoAction` | `NotInEchoes_IsCreated` |
| **Inactive** | `InEchoes_IsDeactivated` | `NotInEchoes_NoAction` |

Four tests, four quadrants. The two `NoAction` cases are the ones people skip, and they are the ones
that catch a reconciler that recreates or re-deactivates on every run.

Plus two resilience tests:

- `ApiError_IsRecordedAndDoesNotThrow`
- `SyncAll_OneFailure_DoesNotStopOthers` -- one bad vehicle must not abandon the batch.

### 4. Fallback paths, with their negative

```
RetrieveAll_ReportUnavailable_FallsBackToVehicleList
RetrieveAll_ReportFailsWithServerError_DoesNotFallBack
```

A fallback that triggers on *every* error hides outages. The pair pins down exactly which failures
are recoverable.

### 5. The "empty body with 200" case

```
GetVehicleByVin_EmptyBodyWith200_ReturnsNull
GetVehicle_EmptyBodyWith200_ReturnsNull
ListVehicles_EmptyBody_ReturnsEmptyList
```

Three tests for one API quirk, because the deserialiser returning `null` for a `200` is the single
most common source of a `NullReferenceException` in production.

If you use the **matcher fake** for these, register an explicit `When(...)` returning 200 -- the
default fallback is 404 and you would be testing the wrong path. See
[http-fakes.md](http-fakes.md).

### 6. Record-type filtering and skip rules

`BillingRecordStorageServiceTests.StoreParkingRowsAsync_SkipsNonParkingFeeRecordTypes` feeds
`ONETIME_FEE`, `SUBSCRIPTION_FEE`, `AUTOMATIC_DISCOUNT` and a `PARKING_FEE` with `Parking = null`,
and asserts nothing is written. Filters are where silent data loss lives -- an over-broad filter
drops real rows and nothing errors.

### 7. Key derivation

`StoreParkingRowsAsync_CreatesSeparateRowPerParkingFeeRecord` -- two records share an `infoId` and
must produce two rows keyed `1001` and `1002`, not one merged row.

This is the highest-value storage test there is. A `RowKey` collision is an **upsert**, so the second
record silently overwrites the first and the row count looks plausible. See
`autoplan-data-persistence/references/entity-conventions.md`.

### 8. Deserialisation of a real captured payload

`DriveOrderModelDeserializationTests`, `ByIterationIdResponseDeserializationTests`,
`SalesContractEntityDriveOrderMappingTests`. Paste a genuine response body captured from the live
API, deserialise it, assert the fields you depend on are populated.

This catches the case where the vendor renames a field: the property silently becomes `null` and
every downstream check still compiles.

## What not to bother with

- Property-by-property mapping assertions where the mapping is a straight copy. Test the mappings
  that **transform** (unit conversion, prefix handling, date normalisation).
- Anything that only re-states the implementation. `Assert.Equal("Apikey " + k, options.ApiKeyHeaderValue)`
  is worth it because the prefix rule has four branches (`ApiKeyHeaderValue_AlwaysCarriesApikeyPrefix`
  is a `[Theory]` with four `[InlineData]`s). A one-line getter is not.
- Logger call verification, unless the log line *is* the contract.

## The limit of a mocked boundary

A `Mock<ISqlDatabaseService>` proves the caller called it. It cannot prove the SQL text is valid,
because the mock never runs it.

That is exactly how HubSpot's suite stayed green while its deals MERGE contained DDL. See the
SKILL.md for the full case.

For SQL bodies and storage bodies specifically, a unit test is the wrong tool. Use the static
checkers, which parse the actual command text:

```powershell
.\scripts\Check-SqlDdlInDml.ps1 -Path <repo>
.\scripts\Check-SqlParameterAlignment.ps1 -ServiceFile <svc.cs> -ModelFile <model1.cs>,<model2.cs>
```

They found the HubSpot defect in one run. No amount of Moq would have.
