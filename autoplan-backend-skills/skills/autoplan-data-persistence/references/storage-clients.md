# Storage clients and DI wiring

## The house pattern (Echoes)

`EchoesIntegration/Program.cs`:

```csharp
// A dedicated data storage account, so integration data is kept separate from the
// account the Functions runtime uses for its own bookkeeping.
var dataStorageConnectionString = builder.Configuration["Echoes:DataStorageConnection"]
    ?? throw new InvalidOperationException("Echoes:DataStorageConnection is not configured");
builder.Services.AddSingleton(new TableServiceClient(dataStorageConnectionString));

builder.Services.AddSingleton<IVehicleStateService, TableVehicleStateService>();
builder.Services.AddSingleton<IOdometerStorageService, TableOdometerStorageService>();
```

Storage service:

```csharp
public class TableOdometerStorageService(
    TableServiceClient tableServiceClient,
    IOptions<EchoesOptions> options) : IOdometerStorageService
{
    private readonly TableClient _table = tableServiceClient.GetTableClient(options.Value.OdometerTableName);
    private bool _tableCreated;
    // ...
}
```

Four things to copy:

1. **Register `TableServiceClient` as a singleton, once.** It is thread-safe and holds the
   connection pool. Constructing one per call leaks sockets.
2. **`GetTableClient(...)` in the service**, from a table name that comes from options -- not a
   literal, not a second connection string.
3. **Fail fast on missing configuration.** `?? throw new InvalidOperationException(...)` at startup
   beats a null reference on the first timer fire.
4. **Register storage services as singletons.** Required for the `_tableCreated` cache to be worth
   anything.

## Multiple storage accounts: keyed services

`EasyparkIntegration/Program.cs` talks to three accounts, so it registers three clients by key:

```csharp
var storageConnectionString = builder.Configuration["AzureWebJobsStorage"]
    ?? throw new InvalidOperationException("AzureWebJobsStorage is not configured");
var billingStorageConnectionString = builder.Configuration["Easypark:BillingStorageConnection"]
    ?? storageConnectionString;
var autoplanCarsStorageConnectionString = builder.Configuration["Easypark:AutoplanCarsStorageConnection"]
    ?? billingStorageConnectionString;

builder.Services.AddKeyedSingleton("StateStorage", new TableServiceClient(storageConnectionString));
builder.Services.AddKeyedSingleton("BillingStorage", new TableServiceClient(billingStorageConnectionString));
builder.Services.AddKeyedSingleton("AutoplanCarsStorage", new TableServiceClient(autoplanCarsStorageConnectionString));
```

Consumed by constructor attribute:

```csharp
public TableBillingRecordStorageService(
    [FromKeyedServices("BillingStorage")] TableServiceClient tableServiceClient,
    ILogger<TableBillingRecordStorageService> logger)
```

Notes:

- **Keys are role names, not account names.** `"BillingStorage"` survives an account rename.
- **Chained fallbacks collapse to one account in dev** and split in production, with no code change
  and no separate registration path. This is the useful part of the pattern.
- Keyed registration requires .NET 8; all Function apps here target .NET 8 isolated.

Use keyed services the moment there is a second account. Two `TableServiceClient` singletons of the
same type cannot otherwise be told apart.

## Options binding

Table and container names belong in options, not in the service:

```csharp
public class EchoesOptions
{
    public string OdometerTableName { get; set; } = "OdometerReadings";
    public string VehicleStateTableName { get; set; } = "VehicleState";
}
```

Drive uses `AzureStorageOptions` with `ConnectionString`, `DriveOrdersTableName`,
`SalesContractsTableName` and `SqlConnectionString` on one object
(`DriveTableStorageService.cs:142-155`). That works, but it also constructs its clients directly:

```csharp
_driveOrdersTableClient = new TableClient(connectionString, driveOrdersTableName);
_salesContractsTableClient = new TableClient(connectionString, salesContractsTableName);
_blobContainerClient = new BlobContainerClient(connectionString, "drivecontracts");
```

Two costs: the connection string is threaded through options into every service that needs a table,
and the blob container name is a literal. Prefer the injected-`TableServiceClient` form -- it keeps
the credential in exactly one place, which matters when you move to managed identity.

## Connection strings

- `AzureWebJobsStorage` is the **runtime's** account (timer leases, singleton locks). Putting
  integration data there is workable but couples your data lifecycle to the host's.
- Give data its own setting -- `Echoes:DataStorageConnection`,
  `Easypark:BillingStorageConnection` -- so it can be moved without touching the runtime.
- Never commit a connection string. `local.settings.json` is git-ignored; production values live in
  App Settings or Key Vault.

## SQL clients

There is no `SqlConnection` singleton and there should not be. `Microsoft.Data.SqlClient` pools
connections internally, so open one per operation and dispose it:

```csharp
using var connection = new SqlConnection(_sqlConnectionString);
await connection.OpenAsync();
```

Hold the **connection string** on the service, not a connection. Both `DriveTableStorageService`
and HubSpot's `SqlDatabaseService` do this correctly.
