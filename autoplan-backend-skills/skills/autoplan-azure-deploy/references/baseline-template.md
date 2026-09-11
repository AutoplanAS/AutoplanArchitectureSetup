# The baseline template

Seven resource types, in dependency order. Source: `EchoesIntegration/infra/main.bicep` (314 lines).
Every integration in the estate has all seven.

## 1. Log Analytics workspace

```bicep
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${prefix}-log'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}
```

First, because App Insights and every diagnostic setting reference it. 30 days is the house
retention; it is also the free tier's included period.

## 2. Application Insights (workspace-based)

```bicep
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}
```

`WorkspaceResourceId` is what makes this workspace-based rather than classic. Classic App Insights
is retired; omitting this is a deployment failure on new resources, not a style choice.

## 3. Host storage account

```bicep
resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${storagePrefix}host${uniqueSuffix}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}
```

This backs `AzureWebJobsStorage` -- timer leases, singleton locks, the content share. It is the
runtime's, not yours.

## 4. Data storage account (conditional)

```bicep
resource dataStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = if (!useSharedDataStorage) {
  name: '${storagePrefix}data${uniqueSuffix}'
  // ...identical hardening
}

var dataStorageConnectionString = useSharedDataStorage
  ? sharedDataStorageConnectionString
  : 'DefaultEndpointsProtocol=https;AccountName=${dataStorage!.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${dataStorage!.listKeys().keys[0].value}'
```

Integration data lives in its own account so its lifecycle is independent of the Functions host.
The `if (...)` plus the `!` non-null assertions are what let dev share one account across all
integrations -- see [environments.md](environments.md).

Note `environment().suffixes.storage` rather than a literal `core.windows.net`. Costs nothing and
makes the template sovereign-cloud safe.

## 5. App Service plan

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${prefix}-plan'
  location: location
  sku: { name: 'Y1', tier: 'Dynamic' }
  properties: { reserved: false }
}
```

`Y1`/`Dynamic` is consumption. `reserved: false` means Windows. Every integration uses this; these
are low-volume scheduled syncs and consumption is the right economics.

Move to `EP1` (Elastic Premium) only for a real reason -- VNet integration, no cold start, or a run
exceeding the 10-minute consumption timeout. It is roughly two orders of magnitude more expensive.

## 6. Function App

```bicep
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${prefix}-func'
  location: location
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [ /* see below */ ]
    }
  }
}
```

The six app settings every integration must have:

| Setting | Value |
|---|---|
| `AzureWebJobsStorage` | host storage connection string |
| `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` | same |
| `WEBSITE_CONTENTSHARE` | `'${prefix}-func'` |
| `FUNCTIONS_EXTENSION_VERSION` | `'~4'` |
| `FUNCTIONS_WORKER_RUNTIME` | `'dotnet-isolated'` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | `appInsights.properties.ConnectionString` |

Then the integration's own settings, prefixed with its config section.

`SystemAssigned` identity is declared everywhere and **currently grants nothing** -- no role
assignment exists in any template. See [gaps.md](gaps.md).

## 7. Diagnostic settings and metric alerts

One diagnostic setting per resource, all pointing at the workspace:

```bicep
resource functionAppDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-loganalytics'
  scope: functionApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [ { category: 'FunctionAppLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}
```

Two baseline alerts, both gated on `enableMonitoringAlerts`:

| Alert | Metric | Threshold | Window |
|---|---|---|---|
| `alert-<name>-<env>-http5xx` | `Http5xx` | Total > 5 | PT5M / PT5M |
| `alert-<name>-<env>-responsetime` | `AverageResponseTime` | Avg > 2000 ms | PT5M / PT15M |

Both use `autoMitigate: true` and route to an optional action group:

```bicep
var metricAlertActions = empty(alertActionGroupResourceId) ? [] : [
  { actionGroupId: alertActionGroupResourceId, webHookProperties: {} }
]
```

Note the consequence: with no `alertActionGroupResourceId`, alerts fire and notify **nobody**. They
are visible in the portal only. Supplying an action group is a deployment-time decision that is
easy to forget.

These two alerts are HTTP-oriented. A timer-triggered integration that never serves HTTP will not
trip either one -- for those, the useful signal is a failure-count or "no successful run in N hours"
alert, which no template currently has.

## Outputs

```bicep
output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output appInsightsName string = appInsights.name
output hostStorageAccountName string = hostStorage.name
output dataStorageAccountName string = useSharedDataStorage ? 'shared-data-storage' : dataStorage!.name
```

Never output a connection string or key. Outputs are stored in deployment history with the same
visibility as parameters.
