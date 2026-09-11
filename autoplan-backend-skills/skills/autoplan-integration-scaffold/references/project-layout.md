# Project layout

Taken from `EchoesIntegration`, which is the reference implementation.

```
<Name>Integration/
├── Api/                      Typed HTTP clients for the external API + token/key providers
├── Http/                     DelegatingHandlers (auth, logging, retry-with-renewal)
├── Services/                 Domain logic and storage services — no HTTP plumbing
├── Entities/                 Azure Table entities (ITableEntity)
├── Models/                   DTOs mirroring the external API's JSON shapes
├── Configuration/            IOptions classes, one per config section
├── Functions/                Triggers only — thin, no business logic
│   └── Diagnostics/          Manual-testing endpoints for the raw external API
├── infra/                    main.bicep, parameters.<env>.bicepparam, provision.ps1
├── <Name>Integration.Tests/  xUnit + Moq
├── Directory.Build.props
├── Directory.Packages.props
├── NuGet.config
├── host.json
├── local.settings.json          (git-ignored)
├── local.settings.example.json  (committed)
├── azure-pipelines.yml          (if using Azure DevOps)
├── .github/
│   └── workflows/
│       └── deploy.yml           (if using GitHub Actions)
├── DOCUMENTATION.md
└── Program.cs
```

Exactly one CI path is required in a new repo: Azure DevOps pipeline or GitHub Actions workflow.

## What goes where

The split that matters most is **`Api/` vs `Services/`**. Getting it wrong is the most common
structural mistake.

| Folder | Contains | Does not contain |
|---|---|---|
| `Api/` | Typed clients. One method per external endpoint. Serialization, pagination, status-code translation. | Business rules, storage, decisions about *why* a call is made |
| `Http/` | `DelegatingHandler` implementations — cross-cutting per-request concerns | Anything endpoint-specific |
| `Services/` | Domain logic, reconciliation, orchestration, storage access | Direct `HttpClient` use — always go through `Api/` |
| `Entities/` | `ITableEntity` classes. Storage shape. | API shapes |
| `Models/` | External API DTOs with `[JsonPropertyName]` | Storage concerns |
| `Functions/` | Triggers. Parse input, call a service, map the result to a response. | Business logic |

`Entities/` and `Models/` are kept separate deliberately even when they look similar. The storage
shape and the API shape change for different reasons, and collapsing them means an upstream API
change rewrites your table schema.

## Functions stay thin

A trigger validates input, calls one service, and maps the result. If a trigger contains a loop
over external data or a branching business rule, that logic belongs in `Services/`.

From `Functions/` in Echoes — HTTP and Timer triggers are paired, both delegating to the same
service, so a scheduled job can always be run on demand:

- `SyncVehicleActivationStateTimer.cs` — scheduled
- `SyncVehicleActivationStateHttp.cs` — same operation, manual

Do this for every scheduled job. Waiting for a cron to fire while debugging is avoidable pain.

## Diagnostics endpoints

`Functions/Diagnostics/` exposes the raw external API for manual testing — listing vehicle types,
checking a privacy key, verifying a configured id is valid. These pay for themselves the first
time a config value is silently wrong.

Echoes' `EchoesOptions.DefaultVehicleTypeId` documents that
`GET /api/diagnostics/vehicle-types` both lists valid ids and validates the setting, because a
wrong value (like the default `0`) makes every vehicle creation fail.

Keep them behind `AuthorizationLevel.Function` like any other endpoint.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Project | `<Name>Integration` | `EchoesIntegration` |
| Test project | `<Name>Integration.Tests` | `EchoesIntegration.Tests` |
| Typed client | `<Name>ApiClient` + `I<Name>ApiClient` | `EchoesApiClient` |
| Second client (different auth) | `<Name>AccountClient` | `EchoesAccountClient` |
| Options | `<Name>Options` with `const string SectionName` | `EchoesOptions` |
| Table entity | `<Thing>Entity` | `VehicleStateEntity` |
| Storage service | `Table<Thing>Service` | `TableVehicleStateService` |
| Handler | `<Name><Concern>Handler` | `EchoesPrivacyKeyHandler` |
| Exception | `<Name>ApiException` | `EchoesApiException` |

## When one project isn't enough

Split into separate projects only when the integrations target genuinely different external
systems with separate lifecycles. `Drive Integration` does this — `DriveFunctions` (Drive orders,
Wayke enrichment) and `SmartCarIntegration` (Smartcar OAuth, telematics webhooks) share a
repository and solution but nothing else.

Do **not** split by layer. One project with the folders above.
