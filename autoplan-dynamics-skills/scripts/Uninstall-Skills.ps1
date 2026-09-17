<#
.SYNOPSIS
    Removes the Autoplan Dynamics skills from one or more AI agents' skills directories.

.DESCRIPTION
    Removes only skill folders from this package (`autoplan-dynamics-*`) and by default only
    when the installed copy came from this repository clone (matching symlink target or
    marker file). Use -IncludeCopies to also remove unmarked directory copies.

.PARAMETER Target
    Which agent(s) to remove from. Defaults to Copilot. Accepts several values.

.PARAMETER IncludeCopies
    Also remove directory copies that do not contain this script's source marker.

.EXAMPLE
    ./scripts/Uninstall-Skills.ps1

.EXAMPLE
    ./scripts/Uninstall-Skills.ps1 -Target Copilot,Claude

.EXAMPLE
    ./scripts/Uninstall-Skills.ps1 -IncludeCopies
#>
[CmdletBinding()]
param(
    [ValidateSet('Copilot', 'Claude', 'Codex', 'Gemini')]
    [string[]]$Target = @('Copilot'),

    [switch]$IncludeCopies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$agentSkillPaths = [ordered]@{
    Copilot = '.agents/skills'
    Claude  = '.claude/skills'
    Codex   = '.codex/skills'
    Gemini  = '.gemini/skills'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'skills'
$targets = @($Target | Select-Object -Unique)
$markerName = '.autoplan-skill-source'

$skills = Get-ChildItem -Path $sourceRoot -Directory |
    Where-Object { $_.Name -like 'autoplan-dynamics-*' -and (Test-Path (Join-Path $_.FullName 'SKILL.md')) }

$removed = 0
$kept = 0

foreach ($agent in $targets) {
    $targetRoot = Join-Path $HOME $agentSkillPaths[$agent]

    if (-not (Test-Path $targetRoot)) {
        Write-Host "$agent - nothing to do, $targetRoot does not exist."
        continue
    }

    Write-Host ''
    Write-Host "$agent -> $targetRoot" -ForegroundColor Cyan

    foreach ($skill in $skills) {
        $skillPath = Join-Path $targetRoot $skill.Name
        if (-not (Test-Path $skillPath)) { continue }

        $existing = Get-Item $skillPath -Force

        $marker = Join-Path $skillPath $markerName
        $isOurCopy = (-not $existing.LinkType) -and (Test-Path $marker) -and
            ((Get-Content $marker -Raw -ErrorAction SilentlyContinue).Trim() -eq $skill.FullName.TrimEnd('\', '/'))
        $isOurLink = $existing.LinkType -and $existing.Target -and
            ((@($existing.Target)[0]).TrimEnd('\', '/') -eq $skill.FullName.TrimEnd('\', '/'))

        if ($isOurLink) {
            $existing.Delete()
            Write-Host "  - $($skill.Name) (link removed)"
            $removed++
        }
        elseif ($existing.LinkType) {
            Write-Warning "  ! $($skill.Name) is a symlink this script did not install. Remove it manually if you want to replace it."
            $kept++
        }
        elseif ($isOurCopy -or $IncludeCopies) {
            Remove-Item $skillPath -Recurse -Force
            Write-Host "  - $($skill.Name) (copy removed)"
            $removed++
        }
        else {
            Write-Warning "  ! $($skill.Name) is a directory this script did not install. Use -IncludeCopies to remove it."
            $kept++
        }
    }
}

Write-Host ''
Write-Host "Removed $removed skill(s) across $($targets.Count) agent(s): $($targets -join ', ')" -ForegroundColor Green
if ($kept -gt 0) {
    Write-Host "Left $kept directory-installed skill(s) in place. Re-run with -IncludeCopies to remove them." -ForegroundColor Yellow
}
