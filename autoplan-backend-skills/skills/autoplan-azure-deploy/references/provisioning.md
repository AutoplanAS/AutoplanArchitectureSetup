# Provisioning locally

`infra/provision.ps1` deploys the same template the pipeline does, from a developer machine. Five
of six integrations have one; OFV does not.

Reference: `EchoesIntegration/infra/provision.ps1`.

## Shape

```powershell
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment,

    [Parameter()]
    [string]$Location = 'norwayeast',

    [Parameter(Mandatory)]
    [string]$EchoesAccountId,

    [Parameter(Mandatory)]
    [System.Security.SecureString]$EchoesApiKey,

    [Parameter()]
    [System.Security.SecureString]$EchoesPrivacyKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resourceGroupName = "rg-echoes-$Environment"
$templateFile = Join-Path $PSScriptRoot 'main.bicep'
$parameterFile = Join-Path $PSScriptRoot "parameters.$Environment.bicepparam"
```

The conventions that matter:

1. **Secrets are `[System.Security.SecureString]`,** so they can be supplied as
   `(Read-Host "API key" -AsSecureString)` and never appear in shell history or in
   `Get-History`. `New-AzResourceGroupDeployment` accepts a `SecureString` directly for a
   `@secure()` parameter.
2. **`[ValidateSet('dev','prod')]`** -- a typo becomes a parameter error, not a new resource group.
3. **`$PSScriptRoot`-relative paths,** so the script works from any working directory.
4. **`Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.** Without the latter,
   a failed `New-AzResourceGroup` prints red text and the script carries on to deploy into nothing.
5. **Both files are existence-checked before anything is created.**
6. **`Get-AzContext` first, `Connect-AzAccount` if absent** -- no silent deploy into whichever
   subscription happened to be selected.
7. **A summary block before deploying,** printing environment, resource group, location and
   **subscription name**. The subscription line is the one that stops a prod accident.
8. **Provisioning state is checked explicitly.** `New-AzResourceGroupDeployment` does not always
   throw on a failed deployment:

```powershell
if ($deployment.ProvisioningState -ne 'Succeeded') {
    Write-Error "Deployment failed with state: $($deployment.ProvisioningState)"
}
```

9. **Outputs are printed at the end** -- function app name, hostname, App Insights, storage
   accounts. Never print a key or connection string.

## Usage

```powershell
./provision.ps1 -Environment dev `
    -EchoesAccountId "12345" `
    -EchoesApiKey (Read-Host "Echoes API key" -AsSecureString)
```

## One thing not to copy

Echoes' script builds the secret parameter names by concatenation (lines 124-128):

```powershell
$secretParameterName = 'echoes' + 'ApiKey'
$deploymentParameters[$secretParameterName] = $EchoesApiKey
```

The obvious reading is that this defeats a secret scanner that pattern-matches on the literal
`echoesApiKey`. Whatever the reason, the parameter *name* is not sensitive -- it is already public
in `main.bicep` and in the pipeline YAML -- and the indirection makes the script harder to read and
breaks find-references. Write it directly:

```powershell
$deploymentParameters['echoesApiKey'] = $EchoesApiKey
```

If a scanner does flag it, suppress the scanner with a documented exclusion rather than obfuscating
the source.

## When to use which

| | `provision.ps1` | Pipeline |
|---|---|---|
| First-time setup of a new environment | yes | |
| Testing a template change before committing | yes | |
| Anything that must be reproducible or audited | | yes |
| Deploying to prod | | yes |

The pipeline runs `az deployment group validate` before `create`; `provision.ps1` does not. For a
dry run locally, add `-WhatIf` to `New-AzResourceGroupDeployment`, or run
`az deployment group validate` by hand first.
