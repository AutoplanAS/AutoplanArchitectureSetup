<#
.SYNOPSIS
    Checks documentation hygiene for an Autoplan integration repo.

.DESCRIPTION
    Reports:
      - episodic markdown filenames (*_SUMMARY, *_FIX, *_UPDATE, FINAL_*, COMPLETION_* ...)
        that describe an act of changing the system rather than its state
      - the untouched Azure DevOps default README template
      - a missing or near-empty readme
      - a missing DOCUMENTATION.md
      - zero-byte markdown files
      - mojibake left by mangled emoji in machine-written docs

    Only the repository root and any docs/ folder are scanned. Nested project
    folders, node_modules, bin and obj are ignored.

    Exit code 1 if any ERROR-level finding is present.

.PARAMETER Path
    Repository root.

.EXAMPLE
    .\Check-DocsHygiene.ps1 -Path 'C:\Kode\DevOps\AutoplanDevelopment\Hubspot Integration'
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

$root = (Get-Item -LiteralPath $Path).FullName

# Filenames describing a change event rather than a system state.
$episodicPatterns = @(
    '_SUMMARY\.md$', '_FIX\.md$', '_UPDATE\.md$', '_UPDATES\.md$',
    '_STATUS_REPORT\.md$', '^COMPLETION_', '^FINAL_', '_VERIFICATION\.md$',
    '_COMPARISON\.md$', '_CHANGE\.md$', '_OPTIMIZATION\.md$', '_REFACTORING'
)

# Sentences from the stock Azure DevOps README that survive only if nobody edited it.
$templateMarkers = @(
    'TODO: Give a short introduction of your project',
    'TODO: Guide users through getting your code up and running',
    'TODO: Describe and show how to build your code'
)

$errorCount = 0
$warnCount = 0

Write-Host "=== $root ===" -ForegroundColor Cyan

$rootDocs = @(Get-ChildItem -LiteralPath $root -Filter '*.md' -File -ErrorAction SilentlyContinue)

$docsDir = Join-Path $root 'docs'
$folderDocs = @()
if (Test-Path -LiteralPath $docsDir) {
    $folderDocs = @(Get-ChildItem -LiteralPath $docsDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
}

$allDocs = @($rootDocs) + @($folderDocs)

if ($allDocs.Count -eq 0) {
    Write-Host "  ERROR  No markdown documentation found." -ForegroundColor Red
    exit 1
}

$totalLines = 0
foreach ($doc in $allDocs) {
    if ($doc.Length -gt 0) {
        $totalLines += @(Get-Content -LiteralPath $doc.FullName -Encoding UTF8).Count
    }
}

Write-Host ("  Markdown files: {0} root, {1} in docs/  ({2} lines total)" -f $rootDocs.Count, $folderDocs.Count, $totalLines)

# --- episodic filenames -------------------------------------------------
foreach ($doc in $allDocs) {
    foreach ($pattern in $episodicPatterns) {
        if ($doc.Name -match $pattern) {
            Write-Host ("  ERROR  Episodic document: {0}. Describes a change, not the system. Move durable content into DOCUMENTATION.md and delete." -f $doc.Name) -ForegroundColor Red
            $errorCount++
            break
        }
    }
}

# --- zero-byte docs -----------------------------------------------------
foreach ($doc in $allDocs) {
    if ($doc.Length -eq 0) {
        Write-Host ("  ERROR  Zero-byte markdown file: {0}" -f $doc.Name) -ForegroundColor Red
        $errorCount++
    }
}

# --- readme -------------------------------------------------------------
$readme = $rootDocs | Where-Object { $_.Name -match '^readme\.md$' } | Select-Object -First 1

if ($null -eq $readme) {
    Write-Host "  ERROR  No README.md at the repository root." -ForegroundColor Red
    $errorCount++
}
else {
    $readmeText = if ($readme.Length -gt 0) {
        [System.IO.File]::ReadAllText($readme.FullName, [System.Text.Encoding]::UTF8)
    } else { '' }

    $isTemplate = $false
    foreach ($marker in $templateMarkers) {
        if ($readmeText -like "*$marker*") { $isTemplate = $true; break }
    }

    if ($isTemplate) {
        Write-Host ("  ERROR  {0} is the untouched Azure DevOps default template." -f $readme.Name) -ForegroundColor Red
        $errorCount++
    }
    elseif (($readmeText -split "`n").Count -lt 20) {
        Write-Host ("  ERROR  {0} has fewer than 20 lines - effectively empty." -f $readme.Name) -ForegroundColor Red
        $errorCount++
    }
}

# --- DOCUMENTATION.md ---------------------------------------------------
$documentation = $rootDocs | Where-Object { $_.Name -match '^DOCUMENTATION\.md$' } | Select-Object -First 1
if ($null -eq $documentation) {
    Write-Host "  WARN   No DOCUMENTATION.md. The house standard is readme.md plus DOCUMENTATION.md." -ForegroundColor Yellow
    $warnCount++
}
else {
    $docText = [System.IO.File]::ReadAllText($documentation.FullName, [System.Text.Encoding]::UTF8)
    if ($docText -notmatch '(?im)^#{1,3}\s.*decisions?\s+log') {
        Write-Host "  WARN   DOCUMENTATION.md has no decisions log. It is the only section that cannot be recovered from the code." -ForegroundColor Yellow
        $warnCount++
    }
    if ($docText -notmatch '(?i)verif') {
        Write-Host "  WARN   DOCUMENTATION.md never uses the word 'verified'. Label observed behaviour separately from assumed." -ForegroundColor Yellow
        $warnCount++
    }
}

# --- mojibake -----------------------------------------------------------
# A lone '?' used as a status marker at the start of a list item or line is
# what remains of an emoji written with the wrong encoding.
foreach ($doc in $allDocs) {
    if ($doc.Length -eq 0) { continue }
    $text = [System.IO.File]::ReadAllText($doc.FullName, [System.Text.Encoding]::UTF8)
    $hits = ([regex]::Matches($text, '(?m)^\s*(?:[-*]\s*)?\?\s+\S')).Count
    if ($hits -gt 0) {
        Write-Host ("  WARN   {0}: {1} line(s) begin with a bare '?' - mangled emoji from a machine-written doc." -f $doc.Name, $hits) -ForegroundColor Yellow
        $warnCount++
    }
}

# --- index smell --------------------------------------------------------
$index = $allDocs | Where-Object { $_.Name -match 'DOCUMENTATION_INDEX\.md$' } | Select-Object -First 1
if ($null -ne $index) {
    Write-Host ("  WARN   {0} exists. An index is a symptom of too many files; fix the sprawl instead." -f $index.Name) -ForegroundColor Yellow
    $warnCount++
}

Write-Host ""
if ($errorCount -gt 0) {
    Write-Host "$errorCount error(s), $warnCount warning(s)." -ForegroundColor Red
    exit 1
}

if ($warnCount -gt 0) {
    Write-Host "0 errors, $warnCount warning(s)." -ForegroundColor Yellow
    exit 0
}

Write-Host "OK" -ForegroundColor Green
exit 0
