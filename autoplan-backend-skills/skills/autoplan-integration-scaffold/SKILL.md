---
name: autoplan-integration-scaffold
description: "Scaffold or align an Autoplan integration to the house standard — .NET 8 Azure Functions isolated worker, project layout, central package versions, DI wiring, IOptions validation, OpenTelemetry and HTTP resilience. WHEN: \"new integration\", \"create an integration\", \"start a new Azure Functions project\", \"scaffold a Functions app\", \"set up a new connector\", \"integrate with <external API>\", \"align this repo to our standard\", \"why is my Program.cs different\", \"which package versions should I use\", \"functions worker restore fails\", \"WorkerExtensions restore error\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration
---

# Autoplan Integration Scaffold

House standard for Autoplan integration projects. Every integration is a **.NET 8 Azure Functions
app on the isolated worker** that talks to a third-party API and persists to Azure Table Storage
and/or SQL.

**EchoesIntegration is the reference implementation.** When another repo does something
differently, Echoes wins unless this document says otherwise.

## Rules

1. **Never invent structure** — use the layout in [references/project-layout.md](references/project-layout.md). Folder names carry meaning; `Api/` and `Services/` are not interchangeable.
2. **Central package management is mandatory** — versions live in `Directory.Packages.props`, never in a `.csproj`. `.csproj` files carry bare `<PackageReference Include="..." />` with no `Version`.
3. **Always ship `NuGet.config`** with an explicit cleared source. Without it the Functions Worker SDK's generated `WorkerExtensions` inner build fails to restore on clean CI agents. This is not optional and not cosmetic — see [references/known-issues.md](references/known-issues.md).
4. **Validate configuration at startup** with `.Validate(...).ValidateOnStart()`. A missing setting must fail the host, not surface later as a confusing 401.
5. ⛔ **Never commit secrets.** `local.settings.json` is git-ignored and a `local.settings.example.json` is committed in its place. This has already gone wrong once in this codebase (OFVIntegration).
6. **Telemetry is OpenTelemetry**, exported to Application Insights only when a connection string is present. Do not add `Microsoft.ApplicationInsights.WorkerService` to new projects.
7. **Every outbound HttpClient gets `AddStandardResilienceHandler`.** No bare `HttpClient`.

## Scaffolding a new integration

Work in this order — later steps depend on earlier ones.

1. **Confirm the name.** `<Name>Integration`, PascalCase, matching the external system (`EchoesIntegration`, `EasyparkIntegration`, `OFVIntegration`). The Azure resource prefix is the lowercase form.
2. **Create the layout** from [references/project-layout.md](references/project-layout.md).
3. **Copy the build files** from `references/templates/`: `Directory.Build.props`, `Directory.Packages.props`, `NuGet.config`, `host.json`, `.gitignore`, `local.settings.example.json`.
4. **Copy `Integration.csproj`** and rename. Note it removes the test project from compilation and sets `CopyToPublishDirectory=Never` on `local.settings.json`.
5. **Write `Program.cs`** from [references/program-cs.md](references/program-cs.md) — DI, options validation, telemetry, resilience, storage.
6. **Write the options class** per [references/configuration.md](references/configuration.md).
7. **Build the API client** — invoke the **`autoplan-external-api-client`** skill.
8. **Wire authentication** — invoke the **`autoplan-integration-auth`** skill.
9. **Add the test project** — `<Name>Integration.Tests`, xUnit + Moq.
10. **Verify** with [references/conformance-checklist.md](references/conformance-checklist.md).

## Aligning an existing integration

Run the checklist in [references/conformance-checklist.md](references/conformance-checklist.md)
and report gaps before changing anything. Known state at the time of writing:

| Repo | Main gaps |
|---|---|
| Autoplan API | no tests, no pipeline, no IaC |
| Easypark | `dotnet test` commented out in pipeline; no `ValidateOnStart`; no resilience handler; still on App Insights |
| OFV | **`local.settings.json` committed with live credentials**; tests disabled; no `Directory.Packages.props` |
| HubSpot | still on App Insights; documentation sprawl (18 root `.md` files, 38 repo-wide); named HTTP client with no resilience |

Fix secrets exposure first, always.

## Non-negotiable file contents

`host.json` is exactly this for a new project — the `telemetryMode` line is what routes Functions
host telemetry through OpenTelemetry:

```json
{
    "version": "2.0",
    "telemetryMode": "OpenTelemetry"
}
```

`.gitignore` must contain `local.settings.json`. Check it before the first commit, not after.

## Reference

- [Project layout](references/project-layout.md)
- [Program.cs and DI wiring](references/program-cs.md)
- [Configuration and options](references/configuration.md)
- [Known issues and workarounds](references/known-issues.md)
- [Conformance checklist](references/conformance-checklist.md)
- Templates: `references/templates/`
