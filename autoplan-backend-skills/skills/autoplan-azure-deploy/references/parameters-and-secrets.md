# Parameters and secrets

## The three-part split

A value reaches the Function App through one of three routes, and choosing the wrong one is how
secrets end up in git.

| Route | Where it lives | Use for |
|---|---|---|
| `.bicepparam` | committed to the repo | non-sensitive per-environment values |
| `--parameters name='$(Var)'` at deploy time | Azure DevOps pipeline variable, secret-flagged | every secret |
| `@description` default in `main.bicep` | committed | stable non-sensitive defaults |

## Declaring a secret parameter

```bicep
@description('Echoes account API key, including the "Apikey " prefix. Only grants access to Global, Account and Privacy-key requests.')
@secure()
param echoesApiKey string

@description('Optional Echoes privacy key... Leave empty to let the app create and renew one automatically.')
@secure()
param echoesPrivacyKey string = ''
```

Rules:

1. **`@secure()` on anything that is a credential.** It suppresses the value in deployment history,
   in `az deployment group show`, and in pipeline logs. Without it the value is stored in plaintext
   in the resource group's deployment history and is readable by anyone with **Reader** on the
   group -- a much wider audience than whoever can read the pipeline.
2. **`@description()` on every parameter, saying what the value is and what it grants.** The Echoes
   descriptions state the blast radius of each key. That is the standard to match.
3. **`@secure()` cannot be reversed.** A secure parameter cannot be read back as a template output.
   If you need the value downstream, pass it, do not output it.
4. **Optional secrets default to `''`,** never to a real value, and the code treats empty as "not
   configured" -- see Echoes' privacy key, which the app mints itself when the parameter is blank.

Constrain non-secret parameters where you can:

```bicep
@minValue(0)
@maxValue(4)
param baselineAlertSeverity int = 2
```

Verify with:

```powershell
.\scripts\Check-BicepBaseline.ps1 -Path <repo-or-main.bicep>
```

It flags any parameter whose name implies a secret (`key`, `password`, `secret`, `token`,
`connectionString`, `credential`) but which lacks `@secure()`. All six templates currently pass.

## Parameter files

`infra/parameters.dev.bicepparam`:

```bicep
using './main.bicep'

param environmentName = 'dev'
param location = 'norwayeast'
param echoesBaseUrl = 'https://api.neutral-server.com'
param echoesApiKey = ''
param echoesPrivacyKey = ''
param echoesAccountId = ''
param echoesDefaultVehicleTypeId = '3465'
param enableMonitoringAlerts = false
param useSharedDataStorage = true
param sharedDataStorageConnectionString = ''
```

- **Every secret is `''`.** The file is committed, so an empty string is the only safe value. The
  real value arrives at deploy time and overrides it.
- **Both files list every parameter,** even where the value is identical, so a diff of
  `parameters.dev` against `parameters.prod` is the complete statement of what differs between
  environments. That readability is worth the duplication.
- **`using './main.bicep'` is mandatory** -- it is what makes the file a `.bicepparam` and gives you
  compile-time checking of parameter names against the template.

## Overriding at deploy time

Later `--parameters` arguments win, so the file supplies the shape and the command supplies the
secrets:

```bash
az deployment group create \
  --resource-group rg-echoes-dev \
  --template-file $(Pipeline.Workspace)/infra/main.bicep \
  --parameters $(Pipeline.Workspace)/infra/parameters.dev.bicepparam \
  --parameters echoesApiKey='$(EchoesApiKey)' \
               echoesPrivacyKey='$(EchoesPrivacyKey)' \
               echoesAccountId='$(EchoesAccountId)' \
               useSharedDataStorage=true \
               sharedDataStorageConnectionString='$(SharedDataStorageConnectionString)'
```

- **Single-quote every `$(Var)`.** Unquoted, a value containing a space or `;` -- which storage
  connection strings always do -- is split into separate arguments and the deploy fails or, worse,
  silently truncates.
- **`$(EchoesApiKey)` must be marked secret in the pipeline variables UI.** Azure DevOps then masks
  it in logs. An unmarked variable is echoed in full.
- **No pipeline uses a variable group** -- all six read pipeline-scoped variables set in the UI.
  That is a deliberate simplification, but it means the same secret is entered once per pipeline
  and there is no single place to rotate it.

## What must never happen

- A real secret in a `.bicepparam`. It is committed.
- A secret in `local.settings.json` in a repo where that file is tracked. `OFVIntegration` has
  exactly this problem -- see `autoplan-integration-auth/references/secrets-management.md`.
- A secret passed without `@secure()` on the receiving parameter.
- A secret in a template `output`.
