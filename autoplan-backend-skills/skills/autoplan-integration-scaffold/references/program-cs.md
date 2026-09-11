# Program.cs and DI wiring

Top-level statements, `FunctionsApplication.CreateBuilder`. The full reference is
`EchoesIntegration/Program.cs`; a ready-to-edit copy is in `templates/Program.cs`.

Order matters — options must be registered before anything resolves them.

## 1. Builder and web application

```csharp
var builder = FunctionsApplication.CreateBuilder(args);
builder.ConfigureFunctionsWebApplication();
```

`ConfigureFunctionsWebApplication()` (not `ConfigureFunctionsWorkerDefaults()`) is what enables
ASP.NET Core integration, so triggers can take `HttpRequest` and return `IActionResult`. It
requires `Microsoft.Azure.Functions.Worker.Extensions.Http.AspNetCore` and
`<FrameworkReference Include="Microsoft.AspNetCore.App" />`.

## 2. Telemetry — opt-in export

```csharp
var otel = builder.Services.AddOpenTelemetry().UseFunctionsWorkerDefaults();
if (!string.IsNullOrEmpty(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    otel.UseAzureMonitorExporter();
}
```

The conditional is the point: with no connection string the app still runs and traces locally, so
local development needs no telemetry configuration at all. An unconditional
`UseAzureMonitorExporter()` fails or spams warnings locally.

Pair this with `"telemetryMode": "OpenTelemetry"` in `host.json` so the Functions host itself
emits OTel rather than classic App Insights.

## 3. Options with startup validation

```csharp
builder.Services.AddOptions<EchoesOptions>()
    .Bind(builder.Configuration.GetSection(EchoesOptions.SectionName))
    .Validate(o => !string.IsNullOrWhiteSpace(o.ApiKey), "Echoes:ApiKey is not configured")
    .Validate(o => o.AccountId > 0, "Echoes:AccountId is not configured")
    .ValidateOnStart();
```

`ValidateOnStart()` fails the host immediately instead of at the first API call. Without it a
missing key surfaces as a 401 or a `NullReferenceException` somewhere far from the cause.

Validate anything whose absence breaks the app. Write the message as the **configuration key**
(`"Echoes:ApiKey is not configured"`) so whoever reads the log knows exactly what to set.

Easypark and HubSpot lack this and pay for it in runtime failures — add it when touching them.

## 4. HTTP clients

Typed clients, never bare `HttpClient`, always with resilience:

```csharp
builder.Services.AddHttpClient<IEchoesApiClient, EchoesApiClient>((sp, client) =>
{
    var options = sp.GetRequiredService<IOptions<EchoesOptions>>().Value;
    client.BaseAddress = new Uri(options.BaseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(100);
})
.AddHttpMessageHandler<EchoesPrivacyKeyHandler>()
.AddStandardResilienceHandler(ConfigureResilience);

static void ConfigureResilience(HttpStandardResilienceOptions o)
{
    o.AttemptTimeout.Timeout = TimeSpan.FromSeconds(30);
    o.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
    o.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
}
```

Three traps, all of which have bitten this codebase:

- **The trailing slash on `BaseAddress` is required.** Without it the last path segment is dropped when combined with a relative URI. Hence `TrimEnd('/') + "/"`.
- **`AttemptTimeout` must be below `TotalRequestTimeout`**, and `CircuitBreaker.SamplingDuration` must be at least double `AttemptTimeout` — otherwise the handler throws at construction, i.e. at startup.
- **Register `DelegatingHandler`s in DI first** (`AddTransient<EchoesPrivacyKeyHandler>()`) before `AddHttpMessageHandler<T>()` can resolve them.

Handler order is outermost-first: `AddHttpMessageHandler` before `AddStandardResilienceHandler`
means auth runs outside retries, so a retried request re-reads the current token.

Details on client design: **`autoplan-external-api-client`** skill.

## 5. Storage

```csharp
var dataStorageConnectionString = builder.Configuration["Echoes:DataStorageConnection"]
    ?? throw new InvalidOperationException("Echoes:DataStorageConnection is not configured");
builder.Services.AddSingleton(new TableServiceClient(dataStorageConnectionString));
```

Data storage is configured **separately from `AzureWebJobsStorage`** so business data can live in
a different account from the Functions runtime's own bookkeeping. Do not reuse
`AzureWebJobsStorage` for application data.

## 6. Services

```csharp
builder.Services.AddSingleton<IVehicleStateService, TableVehicleStateService>();
builder.Services.AddSingleton<IOdometerStorageService, TableOdometerStorageService>();
builder.Services.AddSingleton<IVehicleActivationSyncService, VehicleActivationSyncService>();

builder.Build().Run();
```

## Lifetimes

| Registration | Lifetime | Why |
|---|---|---|
| Typed HTTP clients | (managed by `AddHttpClient`) | Handler pooling |
| `DelegatingHandler` | Transient | Required by `AddHttpMessageHandler` |
| Token / key providers | **Singleton** | The cache is the whole point |
| `TableServiceClient` | Singleton | Thread-safe, expensive to build |
| Domain services | Singleton | Stateless |

**Token providers must be singletons.** Echoes' comment says it plainly: registering the privacy
key provider per-scope would mint a new key on every call. Easypark caches tokens per-client
instance instead, which duplicates token fetches — do not copy that.

## Keyed services

When one integration talks to several accounts or tenants with separate storage, use keyed
services (Easypark's `Program.cs`) rather than a service that switches internally.

## Anti-patterns

| Don't | Do |
|---|---|
| `Microsoft.ApplicationInsights.WorkerService` | OpenTelemetry with conditional exporter |
| `ConfigureFunctionsWorkerDefaults()` | `ConfigureFunctionsWebApplication()` |
| Read config with `Environment.GetEnvironmentVariable` | `IOptions<T>` bound to a section |
| Hardcoded defaults in `Program.cs` | Defaults on the options class |
| Bare `HttpClient` / `new HttpClient()` | Typed client via `AddHttpClient` |
| `BaseAddress` without trailing slash | `TrimEnd('/') + "/"` |
| Scoped token provider | Singleton |
