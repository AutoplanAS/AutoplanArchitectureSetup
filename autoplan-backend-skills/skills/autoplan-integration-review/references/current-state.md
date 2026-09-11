# Verified baseline per repo

Measured directly, not inferred. Every cell was produced by opening the file or running the command
in [checks.md](checks.md). Re-verify before relying on it — repos move.

**Measured:** 2026-08-18.

## Function apps

Nine function apps across seven repos. Drive Integration contains two; HubSpot's `samples/ConsoleSample`
is not a function app and is excluded.

| Repo | Function app | `Program.cs` |
|---|---|---|
| Autoplan API | `AutoplanAPIIntegrations` | 43 lines |
| Drive | `DriveFunctions` | 63 lines |
| Drive | `SmartCarIntegration` | 25 lines |
| Easypark | `EasyparkIntegration` | 60 lines |
| Echoes | `EchoesIntegration` | 104 lines |
| HubSpot | `HubSpotDataRetriever` | 49 lines |
| OFV | `OFVIntegration` | 38 lines |

## Correctness

| Function app | ValidateOnStart | HTTP clients | Resilience | OpenTelemetry |
|---|---|---|---|---|
| **EchoesIntegration** | ✅ | 2 typed | ✅ 2/2 | ✅ |
| AutoplanAPIIntegrations | ✅ | 1 | ❌ 0/1 | ✅ |
| OFVIntegration | ✅ | 1 | ❌ 0/1 | ✅ |
| DriveFunctions | ✅ | 1 | ❌ 0/1 | ❌ |
| SmartCarIntegration | ❌ | 1 | ❌ 0/1 | ❌ |
| EasyparkIntegration | ❌ | 3 | ❌ 0/3 | ❌ |
| HubSpotDataRetriever | ❌ | 1 named¹ | ❌ 0/1 | ❌ |

¹ `services.AddHttpClient("HubSpot")` in `ServiceCollectionExtensions.cs:34`, not `Program.cs`.
A repo-wide search is required — see [false-positives.md](false-positives.md) #2.

**Echoes is the only conformant app.** Resilience is the single most widespread gap: 1 of 7.

## Delivery

| Repo | Pipelines | Bicep | Test projects | Test step | Publishes results |
|---|---|---|---|---|---|
| Echoes | 1 | ✅ | 1 | ✅ `bash: dotnet test` | ✅ |
| Drive | 2 | ✅ | 2 | ✅ `DotNetCoreCLI@2` (DriveFunctions only) | ✅ |
| HubSpot | 1 | ✅ | 1 | ✅ `DotNetCoreCLI@2` | ✅ |
| Easypark | 1 | ✅ | 1 | ⛔ **commented out** (lines 59-64) | ✅ |
| OFV | 1 | ✅ | 1 | ❌ none | ❌ none |
| Autoplan API | ❌ 0 | ❌ 0 | ❌ 0 | — | — |

⛔ **Easypark is the critical case**: `PublishTestResults@2` runs at line 66 while the test task at
lines 59-64 is commented out. The build shows a green test step for a run that never happened.

OFV has a test project and no test step — a gap, but an honest one.

Drive's `SmartCarIntegration/azure-pipelines.yml` has no test step despite a test project existing.

## Structure

| Repo | `Directory.Packages.props` | `NuGet.config` | Largest file |
|---|---|---|---|
| Echoes | ✅ | ✅ | `DiagnosticsHttp.cs` 275 |
| Drive | ✅ | ❌ | `SalesContractEntity.cs` 928 (DTO — fine) |
| Easypark | ✅ | ❌ | `EasyparkPartnerApiClient.cs` 303 |
| HubSpot | ✅ | ❌ | `Types.cs` 1085 (DTO — fine) |
| Autoplan API | ❌ | ❌ | `AutoplanApiClient.cs` 205 |
| OFV | ❌ | ❌ | ⚠️ `OFVApiClient.cs` 455 |

**Echoes is the only repo with `NuGet.config`**, which the Functions Worker SDK needs for its
generated `WorkerExtensions` inner restore on clean CI agents. The others are exposed to that build
failure.

Only `OFVApiClient.cs` is a genuine size finding — it mixes HTTP, auth, parsing and domain logic.
The 928- and 1085-line files are DTO declarations. Never report size without opening the file
([false-positives.md](false-positives.md) #8).

## Security

| Repo | `local.settings.json` tracked | Ignored | Verdict |
|---|---|---|---|
| **OFV** | ⛔ **yes** | ❌ no rule | **Live credentials committed** |
| OFV (`*.bicepparam`) | yes, both envs | — | ✅ secrets empty, injected at deploy |
| HubSpot | no (`.template` only, empty values) | ✅ | ✅ correct practice |
| Echoes, Easypark, Drive, Autoplan API | no | ✅ | ✅ |

⛔ `OFVIntegration/local.settings.json` holds non-empty `OFV__Username`, `OFV__Password` and
`OFV__BaseUrl` for a production endpoint. Confirmed with `git ls-files`, `git check-ignore` (no rule)
and `git show HEAD:...`. **Rotate before anything else.**

HubSpot commits `local.settings.json.template` with empty secret values and ignores the real file —
this is the pattern to copy, and a naive substring search misreports it as a leak
([false-positives.md](false-positives.md) #4).

Other security findings:

- `DriveFunctions/DriveOrderHttpTrigger.cs` — `LogHeaders(req)` runs **before** the auth check, logging the shared secret.
- `DriveFunctions/Services/AuthService.cs` — shared secret compared with `==`, not `FixedTimeEquals`.
- `SmartCarIntegration/SmartCarWebhookTrigger.cs` — no payload signature verification; function key only.
- `SmartCarIntegration/Services/SmartCarAuthService.cs` — credentials read via `Environment.GetEnvironmentVariable(...) ?? string.Empty`, bypassing options validation.

## Priority order across the estate

1. ⛔ **OFV** — rotate and remove the committed credentials.
2. ⛔ **Easypark** — re-enable the test step, or delete the publish step.
3. ⚠️ **Resilience everywhere** — 6 of 7 apps have none. Highest-value single sweep.
4. ⚠️ **`NuGet.config`** — 6 of 7 repos are exposed to the Worker SDK restore failure.
5. ⚠️ **`ValidateOnStart`** — Easypark, HubSpot, SmartCar.
6. ⚠️ **Autoplan API** — no pipeline, no IaC, no tests, despite being a shared dependency.
7. Medium — OFV's 455-line client; Easypark's per-instance token cache; Drive's header logging.
8. Low — telemetry drift (4 apps on App Insights); central package management (Autoplan API, OFV); HubSpot doc sprawl.
