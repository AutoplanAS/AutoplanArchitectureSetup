# Compares SQL parameters used in a service's statements against the properties of the
# model types they bind to. Reports parameters with no matching property, which fail at
# runtime with: Must declare the scalar variable "@Name".
#
# Pass every model type the file binds to -- a service often contains more than one
# statement, each bound to a different model.
#
# Usage:
#   .\Check-SqlParameterAlignment.ps1 -ServiceFile <path> -ModelFile <path>[,<path>...]

param(
    [Parameter(Mandatory = $true)][string]$ServiceFile,
    [Parameter(Mandatory = $true)][string[]]$ModelFile
)

# Identifiers may contain non-ASCII letters. Several models here use Norwegian property
# names written with the actual Norwegian characters, so this character class must be
# Unicode-aware or those names are silently truncated and reported as missing.
$identifier = '[\p{L}_][\p{L}\p{Nd}_]*'

$serviceText = Get-Content -LiteralPath $ServiceFile -Raw -Encoding UTF8

$parameters = [regex]::Matches($serviceText, "@($identifier)") |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

$properties = @()
foreach ($path in $ModelFile) {
    $modelText = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $properties += [regex]::Matches($modelText, "public\s+[\w\?\<\>\[\]\.]+\s+($identifier)\s*\{\s*get") |
        ForEach-Object { $_.Groups[1].Value }
}
$properties = $properties | Sort-Object -Unique

$infrastructure = @('PartitionKey', 'RowKey', 'Timestamp', 'ETag')

$missing = $parameters | Where-Object { $_ -notin $properties }
$unused = $properties | Where-Object { $_ -notin $parameters -and $_ -notin $infrastructure }

Write-Output "SQL parameters: $($parameters.Count)   Model properties: $($properties.Count)"

if ($unused) {
    Write-Output ""
    Write-Output "Model properties never passed to SQL (possible silent data loss):"
    $unused | ForEach-Object { Write-Output "  $_" }
}

if ($missing) {
    Write-Output ""
    Write-Output "Parameters with no matching model property (will throw at runtime):"
    $missing | ForEach-Object { Write-Output "  @$_" }
    exit 1
}

Write-Output ""
Write-Output "All SQL parameters resolve to a model property."
exit 0
