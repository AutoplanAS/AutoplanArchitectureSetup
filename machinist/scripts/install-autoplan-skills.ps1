[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Copilot', 'Claude', 'Codex', 'Gemini')]
    [string[]]$Target = @('Copilot'),

    [Parameter()]
    [ValidateSet('Auto', 'Symlink', 'Copy')]
    [string]$Mode = 'Auto',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$InstallBlueprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$machinistRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $machinistRoot

$backendInstaller = Join-Path $repoRoot 'autoplan-backend-skills\scripts\Install-Skills.ps1'
$webappInstaller = Join-Path $repoRoot 'autoplan-webapp-skills\scripts\Install-Skills.ps1'

if (-not (Test-Path -LiteralPath $backendInstaller -PathType Leaf)) {
    throw "Backend installer not found: $backendInstaller"
}

if (-not (Test-Path -LiteralPath $webappInstaller -PathType Leaf)) {
    throw "Webapp installer not found: $webappInstaller"
}

Write-Host "Installing Autoplan backend skills..."
& $backendInstaller -Target $Target -Mode $Mode -Force:$Force
if (-not $?) {
    throw "Backend skill install failed."
}

Write-Host "Installing Autoplan webapp skills..."
& $webappInstaller -Target $Target -Mode $Mode -Force:$Force
if (-not $?) {
    throw "Webapp skill install failed."
}

if ($InstallBlueprint) {
    Write-Host "Installing blueprint skills via npx..."
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw "npx was not found in PATH. Install Node.js/npm to use -InstallBlueprint."
    }

    & npx skills add owainlewis/blueprint
    if ($LASTEXITCODE -ne 0) {
        throw "Blueprint skill install failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Autoplan skill installation complete for target(s): $($Target -join ', ')"
