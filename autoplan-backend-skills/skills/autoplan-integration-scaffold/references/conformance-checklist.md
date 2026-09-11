# Conformance checklist

Run against a new integration before the first PR, or against an existing one to find drift.
Report gaps before changing anything.

## Security — check first, fix first

- [ ] `local.settings.json` is in `.gitignore`
- [ ] `git ls-files | Select-String "local.settings"` returns nothing
- [ ] No API keys, passwords or connection strings in tracked files, including `.bicepparam`
- [ ] `local.settings.example.json` is committed with empty secret values
- [ ] CI secrets are in secret stores (Azure DevOps secret variables / variable groups, or GitHub secrets), injected via `--parameters`
- [ ] `CopyToPublishDirectory=Never` on `local.settings.json`

A failure here blocks everything else. Rotate the credential before fixing the file.

## Project structure

- [ ] `net8.0`, `AzureFunctionsVersion` `v4`, `OutputType` `Exe`
- [ ] `ImplicitUsings` and `Nullable` both `enable`
- [ ] Folders per [project-layout.md](project-layout.md): `Api/`, `Http/`, `Services/`, `Entities/`, `Models/`, `Configuration/`, `Functions/`
- [ ] Test project `<Name>Integration.Tests` exists and is excluded from the function project's compilation
- [ ] `GenerateDocumentationFile` true with `CS1591` suppressed

## Build configuration

- [ ] `Directory.Packages.props` with `ManagePackageVersionsCentrally`
- [ ] No `Version=` attributes on any `PackageReference`
- [ ] `Directory.Build.props` with `AnalysisLevel` latest and `EnforceCodeStyleInBuild`
- [ ] `NuGet.config` present with `<clear />` and explicit nuget.org
- [ ] Package versions match the house baseline (see `templates/Directory.Packages.props`)

## Program.cs

- [ ] `FunctionsApplication.CreateBuilder` + `ConfigureFunctionsWebApplication()`
- [ ] OpenTelemetry with **conditional** `UseAzureMonitorExporter()`
- [ ] `host.json` has `"telemetryMode": "OpenTelemetry"`
- [ ] No `Microsoft.ApplicationInsights.WorkerService` reference
- [ ] `AddOptions<T>().Bind(...).Validate(...).ValidateOnStart()`
- [ ] Every HTTP client is typed and has `AddStandardResilienceHandler`
- [ ] `BaseAddress` built with `TrimEnd('/') + "/"`
- [ ] Token/key providers registered as **singletons**
- [ ] Data storage connection separate from `AzureWebJobsStorage`

## API client

- [ ] No bare `HttpClient` anywhere; `Services/` never calls HTTP directly
- [ ] Empty-body responses handled (`ReadOrDefaultAsync`)
- [ ] Pagination terminates on a short page and has a max-page guard
- [ ] Failures throw a typed `<Name>ApiException` with status and body
- [ ] `CancellationToken` on every async method, passed all the way down

Detail: **`autoplan-external-api-client`**.

## Authentication

- [ ] Tokens cached in a singleton, not per client instance
- [ ] 401 invalidates the cached token and retries once
- [ ] Request cloned before retry when a body is present
- [ ] Non-standard scheme words set with `TryAddWithoutValidation`

Detail: **`autoplan-integration-auth`**.

## Functions

- [ ] Triggers are thin — parse, call one service, map the result
- [ ] Every timer trigger has an HTTP twin for manual runs
- [ ] `AuthorizationLevel.Function` on all endpoints, diagnostics included
- [ ] Diagnostics endpoints under `Functions/Diagnostics/`

## Tests

- [ ] xUnit + Moq, project builds
- [ ] `MockHttpMessageHandler` used for client tests — no live network calls
- [ ] Auth renewal / 401-retry is covered
- [ ] Pagination termination is covered
- [ ] **Tests actually run in the pipeline** — grep the YAML for a commented-out test task

## CI/CD and infrastructure

- [ ] CI workflow exists: `azure-pipelines.yml` (Azure DevOps) or `.github/workflows/deploy.yml` (GitHub Actions)
- [ ] Five-step release flow: Build → DevInfra → DevApp → ProdInfra → ProdApp
- [ ] Prod stages depend on dev success
- [ ] Tests run in CI and block deploys
- [ ] Azure DevOps only: if repo-level `NuGet.config` is present, use `bash: dotnet test` (see [known-issues.md](known-issues.md))
- [ ] `infra/main.bicep` + `parameters.<env>.bicepparam` per environment
- [ ] Secrets as `@secure()` params supplied from CI secret store

## Documentation

- [ ] `DOCUMENTATION.md` covering architecture, function table, configuration reference, getting started, known issues
- [ ] Every configuration key documented with its effect
- [ ] External API quirks written down where the code works around them

## Current known state

| Repo | Status |
|---|---|
| **Echoes** | Reference implementation — passes |
| Easypark | Tests commented out in pipeline; no `ValidateOnStart`; no resilience; App Insights |
| HubSpot | App Insights; doc sprawl (38 root `.md` files) |
| Drive/SmartCar | Largely conformant; App Insights |
| Autoplan API | No tests, no pipeline, no IaC |
| OFV | **Committed credentials**; tests disabled; no `Directory.Packages.props`; 1-line README; 456-line monolithic client |
| Vercel Vehicle API | Empty — README only |
