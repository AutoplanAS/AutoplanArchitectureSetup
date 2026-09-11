# Deployment steps

## Bicep deploy

```yaml
- task: AzureCLI@2
  displayName: 'Deploy Bicep (Dev)'
  inputs:
    azureSubscription: '$(azureServiceConnection)'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az group create --name rg-echoes-dev --location norwayeast
      az deployment group validate \
        --resource-group rg-echoes-dev \
        --template-file $(Pipeline.Workspace)/infra/main.bicep \
        --parameters $(Pipeline.Workspace)/infra/parameters.dev.bicepparam \
        --parameters echoesApiKey='$(EchoesApiKey)' \
                     echoesPrivacyKey='$(EchoesPrivacyKey)' \
                     echoesAccountId='$(EchoesAccountId)' \
                     useSharedDataStorage=true \
                     sharedDataStorageConnectionString='$(SharedDataStorageConnectionString)'
      az deployment group create \
        --resource-group rg-echoes-dev \
        --template-file $(Pipeline.Workspace)/infra/main.bicep \
        --parameters $(Pipeline.Workspace)/infra/parameters.dev.bicepparam \
        --parameters echoesApiKey='$(EchoesApiKey)' \
                     ... identical ...
```

1. **`az group create` first, unconditionally.** It is idempotent, and it means a brand-new
   environment needs no manual step.
2. **`validate` then `create`, with byte-identical parameters.** Validation catches a template or
   parameter error before anything is changed. The duplication is ugly; keeping the two argument
   lists in sync is a real maintenance cost, and it is the price of the check. If you change one,
   change both -- a `validate` that does not match its `create` validates nothing useful.
3. **`$(Pipeline.Workspace)/infra/...`, not `$(Build.SourcesDirectory)`.** The stage deploys the
   downloaded `infra` artifact, so it deploys the template that was built with this code, not
   whatever is on `main` now.
4. **Single-quote every `$(Var)`.** `sharedDataStorageConnectionString='$(...)'` -- a connection
   string contains `;` and `=`, and unquoted it is mangled.
5. **Environment-specific overrides go on the command line.** Dev passes
   `useSharedDataStorage=true`; prod passes neither it nor the shared connection string, falling
   back to the `.bicepparam` values.

`az deployment group validate` does not report *what will change*. `az deployment group what-if`
does, and nothing uses it -- see [gaps.md](gaps.md).

## Function App deploy

```yaml
- download: current
  artifact: function-app
  displayName: 'Download function-app artifact'

- task: AzureFunctionApp@2
  displayName: 'Deploy Function App (Dev)'
  inputs:
    azureSubscription: '$(azureServiceConnection)'
    appType: 'functionApp'
    appName: 'echoes-dev-func'
    package: '$(Pipeline.Workspace)/function-app/**/*.zip'
    deploymentMethod: 'auto'
```

- **`AzureFunctionApp@2`,** not `AzureWebApp` or `AzureRmWebAppDeployment`.
- **`appType: 'functionApp'`** is Windows. Linux consumption is `functionAppLinux`, and must match
  the plan's `reserved` flag in Bicep -- `reserved: false` means Windows.
- **`appName` is a literal.** This is the one place an environment is hard-coded, because the value
  is needed before any template output is available. Keep it consistent with the Bicep `prefix`
  by hand; nothing checks it, and a typo here deploys nothing while reporting success only after
  a lookup failure.
- **`deploymentMethod: 'auto'`** lets the task choose (zip deploy / run-from-package). All six use
  it.
- **The glob `**/*.zip` must match exactly one file.** It does, because the Build stage publishes
  one project.

## Artifacts

```yaml
- publish: '$(publishPath)'
  artifact: 'function-app'

- publish: '$(Build.SourcesDirectory)/$(infraPath)'
  artifact: 'infra'
```

Two separate artifacts, so:

- an infra-only change can be redeployed without rebuilding, and
- a code-only deploy can skip infra entirely via the `deployDevInfra` / `deployProdInfra`
  parameters,

while both remain versioned together under one build. Each deploy stage downloads only the artifact
it needs (`- download: current` with an explicit `artifact:`), which keeps stage setup fast.

## Ordering within an environment

Infra before app, always. A new app setting must exist before the code that reads it starts. The
reverse order gives you a Function App that starts, fails to find its configuration, and -- if the
options are not validated at startup -- fails at the first timer fire instead of at deploy time.

See `autoplan-integration-scaffold` for startup options validation, which converts that into a
loud, immediate failure.
