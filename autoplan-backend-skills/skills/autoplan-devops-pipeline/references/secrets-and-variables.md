# Secrets and variables

## Where values come from

| Kind | Source | Example |
|---|---|---|
| Build settings | `variables:` block in the YAML | `buildConfiguration`, `dotnetVersion` |
| Service connection | pipeline variable | `$(azureServiceConnection)` |
| Secrets | pipeline variables, **secret-flagged**, set in the UI | `$(EchoesApiKey)` |

**No pipeline in the estate uses a variable group** -- verified across all six. Every secret is a
pipeline-scoped variable configured in the Azure DevOps UI.

That is simple and has one real cost: a secret shared by two pipelines is entered twice, and
rotating it means remembering both. If a secret ever spans pipelines, move it to a variable group
(or better, Key Vault -- see `autoplan-azure-deploy/references/gaps.md`).

## Declaring in YAML

```yaml
variables:
  buildConfiguration: 'Release'
  dotnetVersion: '8.0.x'
  projectPath: 'EchoesIntegration.csproj'
  testProjectPath: 'EchoesIntegration.Tests/EchoesIntegration.Tests.csproj'
  infraPath: 'infra'
  publishPath: '$(Build.ArtifactStagingDirectory)/function-app'
```

Only non-sensitive values. **A secret in the `variables:` block is a secret in git.**

## Using a secret

```bash
--parameters echoesApiKey='$(EchoesApiKey)' \
             sharedDataStorageConnectionString='$(SharedDataStorageConnectionString)'
```

Three rules:

1. **Single-quote every `$(Var)`.** Azure DevOps substitutes the raw text before bash parses the
   line. A storage connection string contains `;` and `=`; unquoted, bash splits on whitespace and
   treats `;` as a command separator. The failure is not always loud -- a truncated value can
   deploy successfully and produce a Function App that cannot reach its storage.
2. **Mark it secret in the UI.** Only then does Azure DevOps mask it in logs. An unmarked variable
   is printed in full whenever a task echoes its command line.
3. **Never `echo` a secret,** not even into a temporary diagnostic step. Masking is best-effort
   string replacement; a base64-encoded or partially-quoted secret defeats it.

Note that masking protects the *log*, not the *deployment record*. That protection comes from
`@secure()` on the receiving Bicep parameter -- see
`autoplan-azure-deploy/references/parameters-and-secrets.md`. Both are needed.

## Naming

Observed conventions, and they are not consistent:

| Repo | Style |
|---|---|
| Echoes | `$(EchoesApiKey)` -- PascalCase |
| OFV | `$(OFV_DEV_PASSWORD)` -- SCREAMING_SNAKE with an environment segment |

The OFV form encodes the environment in the variable name, which is what lets a single config stage
target dev and prod separately. The Echoes form relies on the stage passing the right value.

Either works. Within one pipeline, pick one. Prefer including the environment in the name when the
same secret differs per environment -- it makes an accidental cross-environment use visible in the
diff rather than invisible in the variables UI.

## Service connections

```yaml
inputs:
  azureSubscription: '$(azureServiceConnection)'
```

- Indirected through a variable in all six pipelines, so the connection can be changed without
  editing every task.
- The service principal behind it needs **Contributor** on the subscription or resource group -- it
  creates resource groups (`az group create`).
- Restrict the connection to the specific pipelines that need it in the Azure DevOps UI. Nothing in
  the YAML expresses this.

## Environment gates

```yaml
environment: 'echoes-prod'
```

The approval requirement lives on the environment object in Azure DevOps, **not in this file**. Two
consequences worth internalising:

- You cannot tell from the YAML whether prod is gated. Check the portal.
- Changing a `deployment:` job to a plain `job:` silently removes the gate. The diff looks like a
  formatting change.
- **Verified 2026-08-19: no environment in this project has an approval configured**, prod included.
  See `autoplan-devops-pipeline/references/stages.md`.

## Checklist for a new integration

- [ ] Service connection created and restricted to this pipeline
- [ ] `azureServiceConnection` variable set
- [ ] Every secret added as a **secret-flagged** pipeline variable
- [ ] `<integration>-dev` and `<integration>-prod` environments created
- [ ] Approval gate configured on the prod environment
- [ ] Every `$(Var)` in an inline script single-quoted
- [ ] Every secret parameter in `main.bicep` marked `@secure()`
      (`.\scripts\Check-BicepBaseline.ps1 -Path infra\main.bicep`)
- [ ] Tests actually enforce
      (`.\scripts\Check-PipelineTestEnforcement.ps1 -Path azure-pipelines.yml`)
- [ ] Every deploy stage is gated on build reason **before** any Build Validation policy is created
      (`.\scripts\Check-PipelineDeployGating.ps1 -Path azure-pipelines.yml`)
