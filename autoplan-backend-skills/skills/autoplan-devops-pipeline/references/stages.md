# Stages

## The five

```
Build ──> DeployDevInfra ──> DeployDevApp ──> DeployProdInfra ──> DeployProdApp
```

Source: `EchoesIntegration/azure-pipelines.yml`. All six integrations have exactly these five, in
this order, with these dependencies.

### Header

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

parameters:
  - name: deployDevInfra
    type: boolean
    default: true
  - name: deployProdInfra
    type: boolean
    default: true

variables:
  buildConfiguration: 'Release'
  dotnetVersion: '8.0.x'
  projectPath: 'EchoesIntegration.csproj'
  testProjectPath: 'EchoesIntegration.Tests/EchoesIntegration.Tests.csproj'
  infraPath: 'infra'
  publishPath: '$(Build.ArtifactStagingDirectory)/function-app'
```

- **`main` only.** No PR validation trigger anywhere in the estate -- see [gaps.md](gaps.md).
- **Every path is a variable.** Renaming a project is then a one-line change.
- **Infra toggles default to `true`.** Set one to `false` to redeploy code against unchanged
  infrastructure.

### 1. Build

```yaml
- stage: Build
  displayName: 'Build & Publish'
  jobs:
    - job: Build
      steps:
        - task: UseDotNet@2          # pin the SDK
        - task: DotNetCoreCLI@2      # restore (app)
        - task: DotNetCoreCLI@2      # restore (tests)
        - bash: dotnet test ...      # see testing-in-ci.md
        - task: PublishTestResults@2
        - task: DotNetCoreCLI@2      # publish --no-build
        - publish: '$(publishPath)'                          # artifact: function-app
        - publish: '$(Build.SourcesDirectory)/$(infraPath)'  # artifact: infra
```

Points that matter:

- **`UseDotNet@2` pins `8.0.x`.** Without it you inherit whatever the hosted image ships, which
  changes without notice.
- **Restore the test project separately.** It is not referenced by the app project, so a restore of
  `$(projectPath)` alone does not cover it.
- **`--no-restore` on build, `--no-build` on publish.** Each step consumes the previous step's
  output rather than redoing it. Faster, and it guarantees the artifact is built from the same
  compilation the tests ran against.
- **`zipAfterPublish: true`, `publishWebProjects: false`.** The second is required -- this is not a
  web project and the default would try to detect one.
- **Two artifacts, always.** `infra` is published even when both infra toggles are false, so a
  later manual run can deploy the exact template that matched this build.

### 2 & 4. Infra stages

```yaml
- stage: DeployDevInfra
  dependsOn: Build
  condition: and(succeeded(), eq(${{ parameters.deployDevInfra }}, true))
  jobs:
    - deployment: DeployDevInfrastructure
      environment: 'echoes-dev'
      strategy:
        runOnce:
          deploy:
            steps:
              - download: current
                artifact: infra
              - task: AzureCLI@2
                # az group create; az deployment group validate; az deployment group create
```

Prod is identical but `dependsOn: DeployDevApp` -- **not** `DeployProdInfra`'s natural predecessor
`DeployDevInfra`. That is deliberate: production infrastructure is not touched until the new code
has actually deployed to dev.

### 3 & 5. App stages

```yaml
- stage: DeployDevApp
  dependsOn:
    - Build
    - DeployDevInfra
  condition: and(ne(variables['Build.Reason'], 'PullRequest'), succeeded('Build'), or(eq(${{ parameters.deployDevInfra }}, false), eq(dependencies.DeployDevInfra.result, 'Succeeded'), eq(dependencies.DeployDevInfra.result, 'Skipped')))
```

That condition is the subtle part and is worth reading carefully. The stage runs when the build is
**not** a pull request validation build, `Build` succeeded, **and** either:

- the infra stage was switched off by parameter, or
- it ran and succeeded, or
- it was skipped.

Without the `or(...)`, skipping infra would skip the app deploy too, because a skipped dependency
does not satisfy the default `succeeded()`. Copy this condition verbatim; it is easy to get wrong
and the failure mode is a stage that silently never runs.

`ne(variables['Build.Reason'], 'PullRequest')` must lead **every** `Deploy*` and `Update*Config`
stage. Without it, a Build Validation policy deploys pull request code to production — see
[gaps.md](gaps.md) gap 8.

## The optional config-only stages

Drive and OFV add two more, for seven total:

```yaml
- stage: UpdateDevConfig
  displayName: 'Update App Settings (Dev)'
  dependsOn: Build
  condition: and(ne(variables['Build.Reason'], 'PullRequest'), succeeded('Build'), eq(${{ parameters.updateDevConfig }}, true))
```

`dependsOn: Build` only, and gated on a parameter that defaults to false, so a normal run skips
them entirely. They exist to rotate a credential without a full infra deploy:

```bash
az functionapp config appsettings set \
  --name ofvintegration-dev-func \
  --resource-group rg-ofvintegration-dev \
  --settings \
    "OFV__BaseUrl=$(OFV_DEV_BASE_URL)" \
    "OFV__Username=$(OFV_DEV_USERNAME)" \
    "OFV__Password=$(OFV_DEV_PASSWORD)"
```

**Constraint:** only ever set values that `main.bicep` also declares. Bicep owns the `appSettings`
array wholesale, so a setting introduced here alone survives only until the next infra deploy. See
`autoplan-azure-deploy/references/environments.md`.

## Environments and approvals

```yaml
environment: 'echoes-dev'   # and 'echoes-prod'
```

- Naming is `<integration>-<env>`, matching the Bicep prefix.
- **The approval gate lives on the Azure DevOps environment, not in the YAML.** Nothing in the file
  tells you whether prod requires approval; check the environment in the portal.
- **A `deployment:` job is required for the gate to apply.** Converting one to a plain `job:` for
  convenience removes the approval with no warning and no diff that looks dangerous.
- **As of 2026-08-19, none of the twelve environments has any approval or check configured** —
  including all six `-prod` ones. Verified via the `pipelinesChecks` API, not assumed. Do not treat
  the prod environment as a safety net; today it is not one. List them with:

  ```powershell
  az devops invoke --org $org --area pipelinesChecks --resource configurations `
    --route-parameters project=$proj `
    --query-parameters resourceType=environment resourceId=<envId> --api-version 7.1
  ```
