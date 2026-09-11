[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [Parameter()]
    [string]$Command = 'autoplan-factory-foreman',

    [Parameter()]
    [string]$Model = 'terra',

    [Parameter()]
    [string]$RepositoryPath,

    [Parameter()]
    [string]$WorkerConfigPath,

    [Parameter()]
    [string]$MachinistConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issueToPrDir = $PSScriptRoot
$workflowsDir = Split-Path -Parent $issueToPrDir
$machinistRoot = Split-Path -Parent $workflowsDir
$repoRoot = Split-Path -Parent $machinistRoot

if (-not $RepositoryPath) {
    $RepositoryPath = $repoRoot
}

if (-not $WorkerConfigPath) {
    $WorkerConfigPath = Join-Path $machinistRoot 'worker.toml.example'
}

if (-not $MachinistConfigPath) {
    $MachinistConfigPath = Join-Path $machinistRoot 'config.toml.example'
}

& machinist run `
    --config "$WorkerConfigPath" `
    --machinist-config "$MachinistConfigPath" `
    --command "$Command" `
    --model "$Model" `
    --repo "$RepositoryPath" `
    --prompt "$Prompt"

if ($LASTEXITCODE -ne 0) {
    throw "machinist run failed with exit code $LASTEXITCODE."
}
