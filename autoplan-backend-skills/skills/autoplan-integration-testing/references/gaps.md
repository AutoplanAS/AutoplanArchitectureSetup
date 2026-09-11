# Gaps

Verified across all six test projects, 2026-08-19.

## 1. Half the suites never run

| Repo | Tests | Runs in CI |
|---|---|---|
| Echoes | 47 | yes, `failTaskOnFailedTests: true` |
| Drive + SmartCar | 38 | **no** -- task commented out |
| Easypark | 29 | **no** -- task commented out, publish step still live |
| HubSpot | 3 | yes, skippable at queue time |
| OFV | 0 | no |

67 written, passing tests do not gate any deployment. Easypark's pipeline additionally reports a
successful test step that executed nothing. Full detail in
`autoplan-devops-pipeline/references/testing-in-ci.md`.

This is the largest single gap: the work is already done and switched off.

## 2. Two test files are zero bytes

- `Drive Integration/DriveFunctions.Tests/WaykeGraphQLLookupClientTests.cs` -- 0 bytes
- `Easypark Integration/.../EasyparkIntegration.Tests/Services/EasyparkFleetApiClientTests.cs` -- 0 bytes

They compile and contribute nothing. Their only effect is to make a directory listing suggest that
`WaykeGraphQLLookupClient` and `EasyparkFleetApiClient` are covered. Both are HTTP clients, which is
the one thing in these codebases that is genuinely easy to test.

`OFVIntegration.Tests/OFVApiClientTests.cs` is a 26-line comment naming six test cases it does not
implement, so OFV's test project contains **zero** `[Fact]`s while appearing in the solution as a
test project.

Either write the test or delete the file. An empty test file is a false claim.

## 3. No coverage measurement

No `coverlet.collector` package, no `--collect:"XPlat Code Coverage"`, no ReportGenerator, anywhere.

Nobody is claiming a percentage, which is honest, but it also means nothing flags an entire service
class with no tests at all. Adding the collector is two lines and gives you the "which files have
zero coverage" list, which is the only coverage number worth acting on:

```xml
<PackageReference Include="coverlet.collector" />
```

```yaml
arguments: '--configuration $(buildConfiguration) --collect:"XPlat Code Coverage"'
```

## 4. No integration tests, no Azurite

Every test in the estate is a unit test with all boundaries faked. There is no test that:

- performs a real Azure Table Storage round-trip (no Azurite, no emulator, no test container)
- executes a real SQL statement, even against LocalDB or an in-memory provider
- starts the Functions host

The consequence is specific and has already bitten. Mocked `TableClient` cannot reject a
cross-partition batch, a batch over 100 entities, an unsupported property type, or a `RowKey`
containing `/`. Mocked `ISqlDatabaseService` cannot reject invalid T-SQL -- which is exactly how
HubSpot's deals MERGE survived (see [what-to-test.md](what-to-test.md) and the SKILL.md).

An Azurite-backed test project would close the storage half. For the SQL half, the static checkers
are cheaper and already exist:

```powershell
.\scripts\Check-SqlDdlInDml.ps1 -Path <repo>
.\scripts\Check-SqlParameterAlignment.ps1 -ServiceFile <svc.cs> -ModelFile <models...>
```

## 5. No test for anything Functions-shaped

No test constructs a `TimerInfo`, a `HttpRequestData`, or a `FunctionContext`. The function entry
points -- the timer triggers and HTTP triggers that are the actual product -- are untested in every
repo.

Partly this is justified: the house pattern keeps entry points thin and pushes logic into services,
which is why the service tests are worth more. But `DriveOrderHttpTriggerTests` and
`SmartCarOdometerTriggerTests` show it is possible, so the pattern exists to copy where a trigger has
real branching (input validation, status code selection).

## 6. `[Theory]` is under-used

113 `[Fact]` to 4 `[Theory]`. Sets of near-identical facts differing only by input should be one
theory with `[InlineData]`s -- fewer lines, and adding a case is one line rather than a copied
method.

## 7. No traits, no categories

No `[Trait(...)]` anywhere, so there is no way to run "just the fast ones" or "just the auth ones"
other than by `FullyQualifiedName~` filtering. Fine at this size; worth introducing before a suite
gets slow enough that people stop running it locally.

## 8. No shared test infrastructure

`MockHttpMessageHandler` is implemented **twice**, differently (matcher-based in Echoes, queue-based
in Easypark), plus a third `SequenceHandler` nested inside an Echoes test file. Each is reasonable
in isolation; collectively they are the same hand-copying problem the whole skills repo exists to
address.

No `IClassFixture` or `ICollectionFixture` is used anywhere, so there is also no shared setup within
a project.

**A shared `Autoplan.Testing` package was considered and rejected** (see `docs/roadmap.md`,
decision 2): coupling the integrations to each other costs more than the duplication saves. The
divergence is therefore accepted rather than treated as debt — [http-fakes.md](http-fakes.md)
documents when each of the three designs is the right choice.

What that decision does require is that a fourth copy be a *deliberate* choice of design rather than
whichever file happened to be open. Copy from the skill, not from a sibling repo.

## Priority

1. **Turn the tests back on** (1). 67 tests already exist and enforce nothing.
2. **Fill or delete the empty files** (2).
3. **Add the coverage collector** (3) -- for the zero-coverage file list, not the percentage.
