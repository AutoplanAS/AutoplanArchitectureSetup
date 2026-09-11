# Environments

Two environments, `dev` and `prod`, differing only in parameter values. One template.

## What differs

Diff of `parameters.dev.bicepparam` against `parameters.prod.bicepparam` in Echoes -- three lines:

| Parameter | dev | prod | Why |
|---|---|---|---|
| `environmentName` | `'dev'` | `'prod'` | names every resource |
| `enableMonitoringAlerts` | `false` | `true` | dev noise is not actionable |
| `useSharedDataStorage` | `true` | `false` | cost |

Everything else is identical, deliberately. If dev and prod differ in a way not visible in this
diff, the difference is untracked.

## The shared data storage toggle

Dev integrations point at one shared storage account instead of provisioning one each:

```bicep
param useSharedDataStorage bool = false

@secure()
param sharedDataStorageConnectionString string = ''

resource dataStorage '...' = if (!useSharedDataStorage) { ... }

var dataStorageConnectionString = useSharedDataStorage
  ? sharedDataStorageConnectionString
  : 'DefaultEndpointsProtocol=https;AccountName=${dataStorage!.name};...'
```

- **Default is `false`** -- the safe value. Sharing is opt-in, and prod never opts in.
- **The `!` operators are required.** `dataStorage` is conditional, so Bicep types it as nullable;
  `dataStorage!.name` asserts non-null on the branch where it exists. This is why the ternary cannot
  be simplified.
- **Five of six integrations have this toggle.** OFV does not, because it has no data storage
  account at all.

Same applies to the output:

```bicep
output dataStorageAccountName string = useSharedDataStorage ? 'shared-data-storage' : dataStorage!.name
```

The literal placeholder is deliberate -- referencing `dataStorage!.name` unconditionally would fail
to compile on the shared branch.

**The trade being made:** dev integrations share one blast radius. A dev run that corrupts or
deletes data affects every integration pointing at that account, and dev tables from different
integrations sit side by side. That is acceptable for dev and unacceptable for prod, which is
exactly why the flag is per-environment.

## Alerts

`enableMonitoringAlerts = false` in dev. Both metric alerts are wrapped in
`if (enableMonitoringAlerts)`, so dev provisions neither.

Note the interaction with `alertActionGroupResourceId`: prod has alerts enabled but, unless an
action group id is supplied at deploy time, `metricAlertActions` is `[]` and the alerts notify
nobody. Enabled is not the same as wired up.

## The app settings overwrite trap

**Bicep declares the `appSettings` array in full, and an infra deploy replaces it wholesale.**

Drive and OFV both have `UpdateDevConfig` / `UpdateProdConfig` pipeline stages that apply settings
out-of-band (`OFVIntegration/azure-pipelines.yml:249-255`):

```bash
az functionapp config appsettings set \
  --name ofvintegration-dev-func \
  --resource-group rg-ofvintegration-dev \
  --settings \
    "OFV__BaseUrl=$(OFV_DEV_BASE_URL)" \
    "OFV__Username=$(OFV_DEV_USERNAME)" \
    "OFV__Password=$(OFV_DEV_PASSWORD)"
```

This is genuinely useful -- it rotates a credential in seconds without a full infra deploy. But:

1. **Any setting applied this way that is *not* also a Bicep parameter is erased by the next infra
   deploy.** OFV is safe because `OFV__BaseUrl`, `OFV__Username` and `OFV__Password` are all
   declared in `main.bicep` (lines 133-143) and passed as parameters. Add a fourth setting to the
   config stage only, and it survives exactly until someone deploys infra.
2. **The config stage and the infra stage can disagree.** They read different pipeline variables
   (`$(OFV_DEV_PASSWORD)` versus whatever the infra stage passes). Rotating one and not the other
   leaves the app working until the next infra deploy silently reverts it.

Rule: **the Bicep template is the source of truth for app settings.** A config-only stage may
update a value that Bicep already declares; it must never introduce one Bicep does not.

## Config key style

Two conventions are in use, both valid in .NET:

| Style | Example | Used by |
|---|---|---|
| Colon | `Echoes:ApiKey` | Echoes, Easypark, HubSpot, Drive |
| Double underscore | `OFV__Username` | OFV |

Both bind to `Configuration["OFV:Username"]`. The double-underscore form is the portable one --
it is the only form that survives being set as an environment variable on Linux. Since these apps
run on Windows consumption plans and read from app settings, either works.

Prefer the colon form for consistency with the majority, and be aware that a Linux plan or a
container would force the double-underscore form.

## Adding an environment

To add `staging`:

1. Create `parameters.staging.bicepparam` with `environmentName = 'staging'`.
2. Add the pipeline stages, gated on a parameter, with `environment: '<integration>-staging'`.
3. Create the deployment environment and its approval gate (`<integration>-staging` in Azure
   DevOps environments or GitHub environments).
4. Decide `useSharedDataStorage` and `enableMonitoringAlerts` explicitly.

No template change is needed -- `environmentName` is a free string. Watch the storage name length
budget: `staging` is three characters longer than `prod`.
