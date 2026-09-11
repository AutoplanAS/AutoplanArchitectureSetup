<#
.SYNOPSIS
    Installs the Autoplan skills into one or more AI agents' skills directories.

.DESCRIPTION
    Links every folder under skills/ into each selected agent's skills directory. The skills
    themselves are vendor-neutral SKILL.md files, so the same clone serves every agent that
    implements the Agent Skills format; only the install path differs.

        Copilot   ~/.agents/skills    (CLI, VS Code and the cloud agent)
        Claude    ~/.claude/skills
        Codex     ~/.codex/skills
        Gemini    ~/.gemini/skills

    Symlinks are used when the OS allows it, so a `git pull` updates your skills with no
    reinstall. Without symlink permission the script copies instead and must be re-run after
    pulling; it will tell you which mode it used.

.PARAMETER Target
    Which agent(s) to install into. Defaults to Copilot. Accepts several, and installs into
    each in turn.

.PARAMETER Mode
    Auto (default) tries symlink and falls back to copy. Symlink or Copy force one or the other.

.PARAMETER Force
    Replace existing skill folders that were not installed by this script.

.EXAMPLE
    ./scripts/Install-Skills.ps1

.EXAMPLE
    ./scripts/Install-Skills.ps1 -Target Claude

.EXAMPLE
    ./scripts/Install-Skills.ps1 -Target Copilot,Claude,Codex,Gemini

.EXAMPLE
    ./scripts/Install-Skills.ps1 -Mode Copy -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('Copilot', 'Claude', 'Codex', 'Gemini')]
    [string[]]$Target = @('Copilot'),

    [ValidateSet('Auto', 'Symlink', 'Copy')]
    [string]$Mode = 'Auto',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The skills are portable; only the directory each agent scans differs.
$agentSkillPaths = [ordered]@{
    Copilot = '.agents/skills'
    Claude  = '.claude/skills'
    Codex   = '.codex/skills'
    Gemini  = '.gemini/skills'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'skills'
$targets = @($Target | Select-Object -Unique)

if (-not (Test-Path $sourceRoot)) {
    throw "No skills directory found at '$sourceRoot'. Run this script from a clone of AutoplanCopilotSkills."
}

# A skill is any directory containing a SKILL.md.
$skills = Get-ChildItem -Path $sourceRoot -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }

if (-not $skills) {
    throw "No skills found under '$sourceRoot' (a skill is a folder containing SKILL.md)."
}

function Test-SymlinkSupport {
    # Probing is more reliable than checking for elevation: Windows developer mode grants
    # symlink rights to non-elevated users, and Linux/macOS always allow it.
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("skilllink-" + [guid]::NewGuid())
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Target ([System.IO.Path]::GetTempPath()) -ErrorAction Stop | Out-Null
        Remove-Item $probe -Force -Recurse -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

$useSymlink = switch ($Mode) {
    'Symlink' { $true }
    'Copy'    { $false }
    default   { Test-SymlinkSupport }
}

if ($Mode -eq 'Symlink' -and -not (Test-SymlinkSupport)) {
    throw 'Symlink mode requested but this account cannot create symlinks. Enable Windows developer mode, run elevated, or use -Mode Copy.'
}

$installed = 0
$skipped = 0
$updated = 0

# Written into every copy-installed skill so a later run can recognise its own output and
# refresh it. Symlinks carry that provenance in the link target; copies would not otherwise.
$markerName = '.autoplan-skill-source'

foreach ($agent in $targets) {
    $targetRoot = Join-Path $HOME $agentSkillPaths[$agent]

    if (-not (Test-Path $targetRoot)) {
        New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        Write-Host "Created $targetRoot"
    }

    Write-Host ''
    Write-Host "$agent -> $targetRoot" -ForegroundColor Cyan

    $agentInstalled = 0
    $agentSkipped = 0
    $agentUpdated = 0

    foreach ($skill in $skills) {
        $skillPath = Join-Path $targetRoot $skill.Name
        $isUpdate = $false

        if (Test-Path $skillPath) {
            $existing = Get-Item $skillPath -Force
            $isOurLink = $existing.LinkType -and $existing.Target -and
                         ((@($existing.Target)[0]).TrimEnd('\', '/') -eq $skill.FullName.TrimEnd('\', '/'))

            if ($isOurLink) {
                Write-Host "  = $($skill.Name) (already linked)"
                $agentInstalled++
                continue
            }

            # A copy we made previously: refresh it without needing -Force, so the documented
            # "re-run after every git pull" workflow actually updates anything.
            $marker = Join-Path $skillPath $markerName
            $isOurCopy = (-not $existing.LinkType) -and (Test-Path $marker) -and
                         ((Get-Content $marker -Raw -ErrorAction SilentlyContinue).Trim() -eq $skill.FullName.TrimEnd('\', '/'))

            if (-not ($isOurCopy -or $Force)) {
                Write-Warning "  ! $($skill.Name) already exists at $skillPath and was not installed by this script. Use -Force to replace it."
                $agentSkipped++
                continue
            }

            $isUpdate = $isOurCopy

            # Remove-Item on a directory symlink deletes the link, not the target, but be explicit.
            if ($existing.LinkType) {
                $existing.Delete()
            }
            else {
                Remove-Item $skillPath -Recurse -Force
            }
        }

        if ($useSymlink) {
            New-Item -ItemType SymbolicLink -Path $skillPath -Target $skill.FullName | Out-Null
            Write-Host "  + $($skill.Name) (linked)"
        }
        else {
            Copy-Item -Path $skill.FullName -Destination $skillPath -Recurse -Force
            Set-Content -Path (Join-Path $skillPath $markerName) -Value $skill.FullName.TrimEnd('\', '/') -NoNewline
            if ($isUpdate) {
                Write-Host "  ~ $($skill.Name) (updated)"
                $agentUpdated++
            }
            else {
                Write-Host "  + $($skill.Name) (copied)"
            }
        }
        $agentInstalled++
    }

    Write-Host "  $agentInstalled skill(s) into $targetRoot" -ForegroundColor Green

    $installed += $agentInstalled
    $skipped += $agentSkipped
    $updated += $agentUpdated
}

Write-Host ''
Write-Host "Installed $installed skill(s) across $($targets.Count) agent(s): $($targets -join ', ')" -ForegroundColor Green
if ($updated -gt 0) {
    Write-Host "$updated of them were refreshed from an earlier copy-install." -ForegroundColor Green
}
if ($skipped -gt 0) {
    Write-Host "Skipped $skipped existing skill(s). Re-run with -Force to replace them." -ForegroundColor Yellow
}

if ($useSymlink) {
    Write-Host 'Mode: symlink - future `git pull` updates apply automatically.'
}
else {
    Write-Host 'Mode: copy - re-run this script after every `git pull`.' -ForegroundColor Yellow
    Write-Host 'Tip: enable Windows developer mode to get symlinks and skip that step.'
}

Write-Host ''
if ($targets -contains 'Copilot') {
    Write-Host 'Start a new Copilot session to pick the skills up, then verify with: /skills list'
}
if (@($targets | Where-Object { $_ -ne 'Copilot' }).Count -gt 0) {
    Write-Host 'Start a new session in the other agent(s) to pick the skills up.'
}
