---
name: autoplan-azure-deploy
description: "Azure infrastructure for Autoplan integrations as Bicep: the house Function App template (Log Analytics, App Insights, host and data storage, consumption plan, diagnostic settings, metric alerts), resource naming, dev/prod parameter files, the shared-data-storage cost toggle, @secure() parameter handling, and provision.ps1 for local deploys. WHEN: \"create the infrastructure\", \"write the bicep\", \"main.bicep\", \"provision the function app\", \"add an app setting\", \"deploy to a new environment\", \"resource naming\", \"bicepparam\", \"provision.ps1\", \"storage account for the function\", \"add a metric alert\", \"application insights\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration
---

# Autoplan Azure Deploy

Every integration is provisioned by one `infra/main.bicep` plus a `.bicepparam` per environment,
deployed by the pipeline (see `autoplan-devops-pipeline`) or by `infra/provision.ps1` locally.

Reference: `EchoesIntegration/infra/`. All six integrations already share this shape -- verified
2026-08-19, all six pass the full baseline check. **This is the most consistent artifact in the
estate. Do not invent a new shape; copy Echoes and change the names.**

## Rules

1. **Seven resource types, in this order.** Log Analytics workspace -> Application Insights (linked
   to the workspace) -> host storage -> data storage -> App Service plan -> Function App ->
   diagnostic settings and alerts. See [baseline-template.md](references/baseline-template.md).
2. **`var prefix = '<integration>-${environmentName}'` drives every name.** Never hard-code an
   environment into a resource name. See [naming.md](references/naming.md).
3. **Any parameter carrying a secret is `@secure()`.** Without it the value is written to the
   resource group's deployment history in plaintext, readable by anyone with Reader on the group.
4. **Secrets are never in `.bicepparam`.** The parameter files declare `''` and the real value is
   passed at deploy time. See [parameters-and-secrets.md](references/parameters-and-secrets.md).
5. **App settings are declared in Bicep, in full.** The `appSettings` array is authoritative, so
   anything set out-of-band is erased on the next infra deploy. This bites in a specific,
   documented way -- see [environments.md](references/environments.md).
6. **Dev is cheap, prod is isolated.** `useSharedDataStorage = true` in dev points at one shared
   account; prod provisions its own. Alerts are off in dev, on in prod.
7. **`norwayeast`, consumption plan (`Y1`), .NET 8 isolated.** Uniform across all six integrations.

## The security baseline

Non-negotiable, and currently satisfied everywhere:

```bicep
// Function App
httpsOnly: true
identity: { type: 'SystemAssigned' }
siteConfig: {
  netFrameworkVersion: 'v8.0'
  ftpsState: 'Disabled'
  minTlsVersion: '1.2'
}

// Both storage accounts
supportsHttpsTrafficOnly: true
minimumTlsVersion: 'TLS1_2'
allowBlobPublicAccess: false
```

Check any template with:

```powershell
.\scripts\Check-BicepBaseline.ps1 -Path <repo-or-main.bicep>
```

It verifies all fifteen baseline items and flags parameters whose names imply a secret but which
lack `@secure()`.

## References

- [baseline-template.md](references/baseline-template.md) -- the seven resources, annotated, in deploy order.
- [naming.md](references/naming.md) -- the prefix pattern, storage name constraints, and the one repo that deviates.
- [parameters-and-secrets.md](references/parameters-and-secrets.md) -- `@secure()`, `.bicepparam` files, and how secrets reach the template.
- [environments.md](references/environments.md) -- dev/prod differences, the shared storage toggle, and the app settings overwrite trap.
- [provisioning.md](references/provisioning.md) -- `provision.ps1` for local deploys.
- [gaps.md](references/gaps.md) -- no Key Vault, no SQL in IaC, no managed-identity data access. Know before you assume.
