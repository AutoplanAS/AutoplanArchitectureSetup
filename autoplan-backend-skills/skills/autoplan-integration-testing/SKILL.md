---
name: autoplan-integration-testing
description: "Unit testing for Autoplan integrations with xUnit and Moq: the HTTP handler fakes used to test API clients without a network, testing auth renewal and pagination termination, faking Azure Table Storage (AsyncPageable, SubmitTransactionAsync capture), what is worth testing and what a mocked boundary can never prove. WHEN: \"write tests\", \"unit test\", \"xUnit\", \"Moq\", \"mock the HTTP client\", \"test the API client\", \"MockHttpMessageHandler\", \"test project\", \"how do I test this service\", \"fake table storage\", \"AsyncPageable\", \"the tests pass but it's broken\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration
---

# Autoplan Integration Testing

xUnit + Moq, one `<Project>.Tests` project per integration, `net8.0`, no network, no Azure. All six
integrations have a test project. Only three of them run it.

Reference: `EchoesIntegration.Tests` (5 files, 47 tests) -- the most complete suite in the estate.

## Rules

1. **Never let a unit test touch the network.** Fake at `HttpMessageHandler`, not at your own client
   interface. Faking your own interface tests your mock. See [http-fakes.md](references/http-fakes.md).
2. **Use a reserved domain for base addresses.** `https://api.example.test/` (RFC 6761). A leaked
   live request then fails instead of reaching a third party.
3. **Test the behaviour that is hard to reason about,** not the mapping you can read. Auth
   401-renew-retry, retry termination, pagination termination, reconciliation add/update/remove,
   record-type filtering, deserialisation of a real captured payload. See
   [what-to-test.md](references/what-to-test.md).
4. **Every retry needs a negative test.** `On401_RenewsKeyAndRetriesOnce` is only half of it;
   `On401Twice_DoesNotRetryForever` is what proves the loop terminates.
5. **Mocking the boundary you are worried about proves nothing about it.** A passing
   `Verify(s => s.SaveDealsAsync(...), Times.Once)` says the orchestrator called the method. It says
   nothing about whether the method works. This is not hypothetical -- see below.
6. **`NullLogger<T>.Instance` unless you are asserting on logs.** A `Mock<ILogger<T>>` you never
   verify is noise. The estate is split 7/10 on this; prefer `NullLogger`.
7. **A test project that does not run in CI is not a test project.** See
   `autoplan-devops-pipeline/references/testing-in-ci.md`.

## The case that makes rule 5 concrete

`HubSpotDataRetriever.Tests` has three tests. They pass. CI runs them. HubSpot deals have never
reached SQL.

`HubSpotSyncOrchestrationServiceTests.cs:87` asserts:

```csharp
_sqlDatabaseService.Verify(s => s.SaveDealsAsync(
    It.IsAny<IEnumerable<DealDbModel>>(), It.IsAny<CancellationToken>()), Times.Once);
```

`ISqlDatabaseService` is a `Mock`. The real `SqlDatabaseService.SaveDealsAsync` has DDL column
definitions pasted into the `UPDATE SET` clause of its MERGE (`SqlDatabaseService.cs:432-445`) and
swallows the resulting `SqlException` (`492-497`). The mock never executes any of it.

Line 75 asserts `Assert.Equal(1, result.DealsProcessed)` -- which also passes, because the count
returned is the number of deals *retrieved*, not the number persisted
(`HubSpotSyncOrchestrationService.cs:101`).

So the suite asserts precisely the behaviour that is broken, and is green. The lesson is not "don't
use Moq". It is: **a mock verifies a call, and the defect was inside the callee.** Something has to
exercise the real SQL text -- see [what-to-test.md](references/what-to-test.md).

## Current state

Verified 2026-08-19:

| Repo | Test files | Tests | Runs in CI |
|---|---|---|---|
| Echoes | 5 | 47 | yes, enforced |
| Drive + SmartCar | 9 | 38 | **no** |
| Easypark | 7 | 29 | **no** (and reports success) |
| HubSpot | 1 | 3 | yes, skippable |
| OFV | 1 | **0** | **no** |

Two test files in the estate are **zero bytes**:

- `Drive Integration/DriveFunctions.Tests/WaykeGraphQLLookupClientTests.cs`
- `Easypark Integration/.../EasyparkIntegration.Tests/Services/EasyparkFleetApiClientTests.cs`

They compile, contribute nothing, and make the file list look like coverage exists.
`OFVIntegration.Tests/OFVApiClientTests.cs` is a 26-line comment block listing six test cases it
does not implement -- so OFV's test project contains zero `[Fact]`s.

```powershell
.\scripts\Check-TestSuiteHealth.ps1 -Path <repo>
```

## References

- [http-fakes.md](references/http-fakes.md) -- the three handler fakes in use, when to pick each, and the trap in the matcher-based one.
- [what-to-test.md](references/what-to-test.md) -- the behaviours worth covering, with the real test that covers each.
- [azure-storage-fakes.md](references/azure-storage-fakes.md) -- faking `TableClient`, `AsyncPageable<T>` and `SubmitTransactionAsync`.
- [conventions.md](references/conventions.md) -- project layout, naming, loggers, options, central package management.
- [gaps.md](references/gaps.md) -- no coverage measurement, no integration tests, no Azurite, empty test files.
