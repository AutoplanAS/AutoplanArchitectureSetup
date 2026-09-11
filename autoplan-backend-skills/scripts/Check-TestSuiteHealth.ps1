<#
.SYNOPSIS
    Reports test-suite health for Autoplan integration repos.

.DESCRIPTION
    Finds *.Tests projects under -Path and reports, per test project:
      - empty (zero-byte) test files
      - test files containing no [Fact] or [Theory]
      - total test count
      - base addresses that are not RFC 6761 reserved domains
      - Mock<ILogger> usage where NullLogger would do

    Exit code 1 if any ERROR-level finding is present.

.PARAMETER Path
    A repository root, a solution folder, or a single *.Tests.csproj.

.EXAMPLE
    .\Check-TestSuiteHealth.ps1 -Path 'C:\Kode\DevOps\AutoplanDevelopment\EchoesIntegration'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Path not found: $Path"
    exit 2
}

$item = Get-Item -LiteralPath $Path
if ($item.PSIsContainer) {
    $projects = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*Tests*.csproj' -File -ErrorAction SilentlyContinue)
}
else {
    $projects = @($item)
}

if ($projects.Count -eq 0) {
    Write-Host "No test projects found under $Path" -ForegroundColor Yellow
    exit 0
}

# RFC 6761 reserved names plus loopback. Anything else is a registrable domain.
$reservedHostPattern = '(\.test|\.example|\.invalid|\.localhost|^localhost|^127\.0\.0\.1)'

$errorCount = 0

foreach ($project in $projects) {
    $dir = $project.Directory.FullName
    Write-Host ""
    Write-Host "=== $($project.Name) ===" -ForegroundColor Cyan

    $sourceFiles = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.cs' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\obj\\|\\bin\\' })

    if ($sourceFiles.Count -eq 0) {
        Write-Host "  ERROR  Test project contains no .cs files." -ForegroundColor Red
        $errorCount++
        continue
    }

    $totalTests = 0
    $emptyFiles = @()
    $testlessFiles = @()
    $liveHosts = @()
    $mockLoggerFiles = @()

    foreach ($file in $sourceFiles) {
        # Generated and infrastructure files are not test files.
        if ($file.Name -match 'AssemblyInfo|GlobalUsings|AssemblyAttributes') { continue }

        if ($file.Length -eq 0) {
            $emptyFiles += $file
            continue
        }

        # PowerShell 5.1 reads BOM-less UTF-8 as ANSI without an explicit encoding.
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)

        $factCount = ([regex]::Matches($text, '\[\s*(Fact|Theory)\b')).Count
        $totalTests += $factCount

        $looksLikeTestFile = $file.Name -match 'Tests?\.cs$'
        $isHelper = $file.DirectoryName -match '\\Helpers?$'

        if ($looksLikeTestFile -and -not $isHelper -and $factCount -eq 0) {
            $testlessFiles += $file
        }

        foreach ($m in [regex]::Matches($text, 'https?://[^"''\s\)]+')) {
            $uri = $m.Value
            $hostPart = $uri -replace '^https?://', '' -replace '[/:].*$', ''
            if ($hostPart -notmatch $reservedHostPattern) {
                $liveHosts += [pscustomobject]@{ File = $file.Name; Uri = $uri }
            }
        }

        if ($text -match 'Mock<ILogger') {
            $mockLoggerFiles += $file.Name
        }
    }

    Write-Host ("  Tests found: {0}" -f $totalTests)

    if ($totalTests -eq 0) {
        Write-Host "  ERROR  Test project contains zero [Fact]/[Theory] methods." -ForegroundColor Red
        $errorCount++
    }

    foreach ($f in $emptyFiles) {
        Write-Host ("  ERROR  Empty test file (0 bytes): {0}" -f $f.Name) -ForegroundColor Red
        $errorCount++
    }

    foreach ($f in $testlessFiles) {
        Write-Host ("  ERROR  Test file with no [Fact]/[Theory]: {0}" -f $f.Name) -ForegroundColor Red
        $errorCount++
    }

    foreach ($group in ($liveHosts | Group-Object Uri)) {
        $files = ($group.Group | Select-Object -ExpandProperty File | Sort-Object -Unique) -join ', '
        Write-Host ("  WARN   Non-reserved host in test: {0} ({1}). Prefer https://api.example.test/" -f $group.Name, $files) -ForegroundColor Yellow
    }

    if ($mockLoggerFiles.Count -gt 0) {
        Write-Host ("  INFO   Mock<ILogger> used in: {0}. NullLogger<T>.Instance is preferred unless asserting on logs." -f (($mockLoggerFiles | Sort-Object -Unique) -join ', ')) -ForegroundColor DarkGray
    }

    if ($totalTests -gt 0 -and $emptyFiles.Count -eq 0 -and $testlessFiles.Count -eq 0) {
        Write-Host "  OK" -ForegroundColor Green
    }
}

Write-Host ""
if ($errorCount -gt 0) {
    Write-Host "$errorCount error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "No errors." -ForegroundColor Green
exit 0
