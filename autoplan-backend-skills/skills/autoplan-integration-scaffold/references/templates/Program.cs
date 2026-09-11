using Azure.Data.Tables;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Http.Resilience;
using Microsoft.Extensions.Options;
using OpenTelemetry;
using <Name>Integration.Api;
using <Name>Integration.Configuration;
using <Name>Integration.Services;

// <Name> integration — Azure Functions (.NET 8 isolated worker).
//
// Describe here, in a few lines, what this integration does and how data flows through it.
// A future reader should learn the shape of the system without opening another file.
//
// Flow:
//   <source> -> <service that decides> -> <external API / storage>
//   Timer triggers drive it on a schedule, HTTP triggers on demand.
var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

// App Insights export is opt-in: without a connection string the app still runs and traces
// locally, so no configuration is needed for local testing.
var otel = builder.Services.AddOpenTelemetry().UseFunctionsWorkerDefaults();
if (!string.IsNullOrEmpty(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    otel.UseAzureMonitorExporter();
}

// ValidateOnStart fails the host immediately on missing configuration rather than at the first
// API call, which otherwise shows up as a confusing 401 or NullReference at runtime.
builder.Services.AddOptions<<Name>Options>()
    .Bind(builder.Configuration.GetSection(<Name>Options.SectionName))
    .Validate(o => !string.IsNullOrWhiteSpace(o.ApiKey), "<Name>:ApiKey is not configured")
    .ValidateOnStart();

builder.Services.AddHttpClient<I<Name>ApiClient, <Name>ApiClient>((sp, client) =>
{
    var options = sp.GetRequiredService<IOptions<<Name>Options>>().Value;
    // The trailing slash matters: without it the last path segment of BaseAddress is dropped
    // when combined with a relative request URI.
    client.BaseAddress = new Uri(options.BaseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(100);
})
.AddStandardResilienceHandler(ConfigureResilience);

// AttemptTimeout must stay below TotalRequestTimeout, and CircuitBreaker.SamplingDuration must be
// at least double AttemptTimeout, or the handler throws while the host is starting.
static void ConfigureResilience(HttpStandardResilienceOptions o)
{
    o.AttemptTimeout.Timeout = TimeSpan.FromSeconds(30);
    o.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
    o.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
}

// Storage is configured separately from AzureWebJobsStorage so the data tables can live in a
// different account from the one the Functions runtime uses for its own bookkeeping.
var dataStorageConnectionString = builder.Configuration["<Name>:DataStorageConnection"]
    ?? throw new InvalidOperationException("<Name>:DataStorageConnection is not configured");
builder.Services.AddSingleton(new TableServiceClient(dataStorageConnectionString));

builder.Services.AddSingleton<I<Thing>StateService, Table<Thing>StateService>();

builder.Build().Run();
