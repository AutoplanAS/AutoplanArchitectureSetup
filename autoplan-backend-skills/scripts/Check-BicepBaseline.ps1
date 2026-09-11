# Checks a main.bicep against the Autoplan Function App baseline: observability wiring,
# transport and storage hardening, runtime pinning, and secure parameter handling.
#
# The highest-value check is the last one. A parameter whose name implies a secret but
# which lacks @secure() has its value stored in plaintext in the resource group's
# deployment history, readable by anyone with Reader on the group.
#
# Usage:
#   .\Check-BicepBaseline.ps1 -Path <main.bicep or repo root>

param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Path -PathType Container) {
    $files = Get-ChildItem -LiteralPath $Path -Recurse -Filter 'main.bicep' -File
} else {
    $files = @(Get-Item -LiteralPath $Path)
}

if (-not $files) {
    Write-Output "No main.bicep found under '$Path'."
    exit 0
}

# Baseline assertions. Each is a name and a regex that must be present.
$baseline = [ordered]@{
    'Log Analytics workspace'          = 'Microsoft\.OperationalInsights/workspaces'
    'Application Insights'             = 'Microsoft\.Insights/components'
    'App Insights linked to workspace' = 'WorkspaceResourceId'
    'Diagnostic settings'              = 'Microsoft\.Insights/diagnosticSettings'
    'Metric alerts'                    = 'Microsoft\.Insights/metricAlerts'
    'Managed identity'                 = "type:\s*'SystemAssigned'"
    'HTTPS only'                       = 'httpsOnly:\s*true'
    'FTPS disabled'                    = "ftpsState:\s*'Disabled'"
    'Site min TLS 1.2'                 = "minTlsVersion:\s*'1\.2'"
    'Storage min TLS 1.2'              = "minimumTlsVersion:\s*'TLS1_2'"
    'Storage HTTPS only'               = 'supportsHttpsTrafficOnly:\s*true'
    'Blob public access disabled'      = 'allowBlobPublicAccess:\s*false'
    'Functions runtime v4'             = "FUNCTIONS_EXTENSION_VERSION"
    'Isolated worker runtime'          = "'dotnet-isolated'"
    '.NET 8 pinned'                    = "netFrameworkVersion:\s*'v8\.0'"
}

# A parameter name matching this is expected to carry a secret value.
$secretNamePattern = 'key|password|secret|token|connectionstring|apikey|credential'
# ...unless its name ends in one of these, which denote a name, location or identifier
# rather than the secret itself (e.g. smartcarTokensTableName, keyVaultName, accountId).
$secretNameSuffixExceptions = '(name|url|uri|id|enabled|count|version|prefix)$'

$exitCode = 0

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8

    Write-Output "=== $($file.FullName) ==="

    $missing = @()
    foreach ($entry in $baseline.GetEnumerator()) {
        if ($text -notmatch $entry.Value) { $missing += $entry.Key }
    }

    if ($missing.Count -eq 0) {
        Write-Output "  OK  All $($baseline.Count) baseline items present."
    } else {
        foreach ($m in $missing) {
            Write-Output "  WARN   Baseline item missing: $m"
        }
        $exitCode = 1
    }

    # Secure parameter check. Walk parameters and look back for an @secure() decorator.
    $insecure = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '^\s*param\s+([A-Za-z_][A-Za-z0-9_]*)\s')
        if (-not $m.Success) { continue }

        $name = $m.Groups[1].Value
        $lower = $name.ToLowerInvariant()
        if ($lower -notmatch $secretNamePattern) { continue }
        if ($lower -match $secretNameSuffixExceptions) { continue }

        # Decorators sit on the lines immediately above, possibly with @description between.
        $secure = $false
        for ($j = $i - 1; $j -ge 0 -and $j -ge $i - 5; $j--) {
            $prev = $lines[$j]
            if ($prev -match '@secure\(\)') { $secure = $true; break }
            if ($prev -notmatch '^\s*(@|//|$)') { break }
        }

        if (-not $secure) { $insecure += "$name (line $($i + 1))" }
    }

    if ($insecure.Count -gt 0) {
        Write-Output ""
        Write-Output "  ERROR  Parameters that look like secrets but are not marked @secure():"
        $insecure | ForEach-Object { Write-Output "    $_" }
        Write-Output "         Their values are stored in plaintext in the deployment history."
        $exitCode = 1
    }

    Write-Output ""
}

exit $exitCode
