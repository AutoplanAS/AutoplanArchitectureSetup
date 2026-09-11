# Naming

## The pattern

```bicep
var prefix = 'echoes-${environmentName}'
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)
var storagePrefix = replace(prefix, '-', '')
```

Everything derives from those three.

| Resource | Expression | Example (dev) |
|---|---|---|
| Resource group | `rg-<integration>-<env>` | `rg-echoes-dev` |
| Log Analytics | `${prefix}-log` | `echoes-dev-log` |
| App Insights | `${prefix}-ai` | `echoes-dev-ai` |
| App Service plan | `${prefix}-plan` | `echoes-dev-plan` |
| Function App | `${prefix}-func` | `echoes-dev-func` |
| Host storage | `${storagePrefix}host${uniqueSuffix}` | `echoesdevhosta1b2` |
| Data storage | `${storagePrefix}data${uniqueSuffix}` | `echoesdevdataa1b2` |
| Metric alert | `alert-<integration>-<env>-<signal>` | `alert-echoes-dev-http5xx` |
| Diagnostic setting | `send-to-loganalytics` | (constant) |
| Pipeline environment | `<integration>-<env>` | `echoes-dev` |

The resource group name is **not** built by the template -- it is created by the pipeline
(`az group create --name rg-echoes-dev`) and by `provision.ps1`
(`$resourceGroupName = "rg-echoes-$Environment"`). Keep the two in step by hand; nothing enforces it.

## Why storage names are different

Storage account names have their own rules: 3-24 characters, lowercase letters and digits only, and
**globally unique across all of Azure**. Hence:

- `replace(prefix, '-', '')` strips the hyphens the other resources keep.
- `substring(uniqueString(resourceGroup().id), 0, 4)` appends a deterministic suffix derived from
  the resource group id, so the name is stable across redeploys but unlikely to collide with
  another tenant's.

Watch the 24-character budget: `<integration><env>data<4>`. With `environmentName = 'prod'` that
leaves 14 characters for the integration name before the data account overflows. Keep integration
names short.

## The deviation

Five integrations use the short integration name; OFV uses the repo name:

| Repo | prefix |
|---|---|
| EchoesIntegration | `echoes-${environmentName}` |
| EasyparkIntegration | `easypark-${environmentName}` |
| HubSpotDataRetriever | `hubspot-${environmentName}` |
| DriveFunctions | `drive-${environmentName}` |
| SmartCarIntegration | `smartcar-${environmentName}` |
| OFVIntegration | `ofvintegration-${environmentName}` |

`ofvintegration-` is 14 characters, which does not fit the storage naming budget. OFV works around
this rather than fixing the prefix, and in doing so departs from the pattern twice
(`OFVIntegration/infra/main.bicep:30-31`):

```bicep
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)   // 6, not 4
var storageName = 'ofvint${environmentName}${uniqueSuffix}'            // hand-abbreviated,
                                                                       // not replace(prefix, '-', '')
```

So `ofvint` appears nowhere else in the template, and the storage name cannot be derived from the
prefix the way it can in the other five. OFV also declares only one storage account, so it never
hits the `data` variant.

The fix is the prefix, not the workaround: `ofv-${environmentName}`. Renaming existing resources
means recreating them, so treat this as a rule for new integrations and a cleanup task for OFV, not
a silent retrofit.

## Rules

1. **Never hard-code an environment.** `echoes-dev-func` must only ever appear as
   `'${prefix}-func'`. The one legitimate exception is the pipeline's `appName:` input, which is a
   literal because it is consumed before any template output exists.
2. **Never hard-code a region.** `location` defaults to `resourceGroup().location` and is set
   explicitly in the `.bicepparam`. All environments are `norwayeast`.
3. **Lowercase, hyphen-separated, short.** The integration name is a single word where possible.
4. **The deployment environment name matches the prefix.** `environment: 'echoes-dev'` in the CI
   YAML corresponds to `rg-echoes-dev`. This is convention only -- either platform can let them
   diverge, and then approval gates apply to the wrong thing.
