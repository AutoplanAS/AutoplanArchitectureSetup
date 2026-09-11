# Checks that GitHub Actions deploy jobs are gated off pull request validation builds.
#
# Usage:
#   .\Check-GitHubWorkflowDeployGating.ps1 -Path <repo root or workflow.yml>
#   .\Check-GitHubWorkflowDeployGating.ps1 -Path <repo> -DefaultBranches main,develop

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string[]]$DefaultBranches = @('main', 'master', 'trunk')
)

$ErrorActionPreference = 'Stop'

function Get-WorkflowFiles {
    param([string]$InputPath)

    if (Test-Path -LiteralPath $InputPath -PathType Container) {
        return @(
            Get-ChildItem -LiteralPath $InputPath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension -in '.yml', '.yaml' -and
                    $_.FullName -match '[\\/]\.github[\\/]workflows[\\/]' -and
                    $_.FullName -notmatch '[\\/](obj|bin|node_modules|\.git)[\\/]'
                }
        )
    }

    return @(Get-Item -LiteralPath $InputPath)
}

function Get-Jobs {
    param([string[]]$Lines)

    $jobsStart = -1
    $jobsIndent = 0
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*#') { continue }
        if ($Lines[$i] -match '^(?<indent>\s*)jobs:\s*$') {
            $jobsStart = $i
            $jobsIndent = $Matches['indent'].Length
            break
        }
    }

    if ($jobsStart -lt 0) { return @() }

    $jobs = @()
    for ($i = $jobsStart + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }

        if ($line -match "^(?<indent>\s*)(?<id>[A-Za-z0-9_-]+):\s*(#.*)?$") {
            $indent = $Matches['indent'].Length
            if ($indent -eq ($jobsIndent + 2)) {
                $jobs += [pscustomobject]@{
                    Id       = $Matches['id']
                    Line     = $i
                    Indent   = $indent
                    PropCol  = $indent + 2
                }
                continue
            }
        }

        $trimmed = $line.Trim()
        if ($trimmed -and (($line.Length - $trimmed.Length) -le $jobsIndent)) {
            break
        }
    }

    for ($j = 0; $j -lt $jobs.Count; $j++) {
        $end = if ($j + 1 -lt $jobs.Count) { $jobs[$j + 1].Line - 1 } else { $Lines.Count - 1 }
        $jobs[$j] | Add-Member -NotePropertyName EndLine -NotePropertyValue $end
    }

    return $jobs
}

function Get-PushBranches {
    param([string[]]$Lines)

    $branches = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -notmatch '^(?<indent>\s*)push:\s*$') { continue }

        $pushIndent = $Matches['indent'].Length
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            $candidate = $Lines[$j]
            if ($candidate -match '^\s*#' -or $candidate -match '^\s*$') { continue }

            $indent = $candidate.Length - $candidate.TrimStart().Length
            if ($indent -le $pushIndent) { break }

            if ($candidate -match "^\s{$($pushIndent + 2)}branches:\s*(?<value>.*)$") {
                $value = $Matches['value'].Trim()
                if ($value -match '^\[(?<inline>.+)\]$') {
                    $branches += @(
                        $Matches['inline'] -split ',' |
                            ForEach-Object { $_.Trim().Trim("'", '"') } |
                            Where-Object { $_ -ne '' }
                    )
                }
                else {
                    for ($k = $j + 1; $k -lt $Lines.Count; $k++) {
                        $branchLine = $Lines[$k]
                        if ($branchLine -match '^\s*#' -or $branchLine -match '^\s*$') { continue }

                        $branchIndent = $branchLine.Length - $branchLine.TrimStart().Length
                        if ($branchIndent -le ($pushIndent + 2)) { break }

                        if ($branchLine -match "^\s{$($pushIndent + 4)}-\s*(?<branch>.+?)\s*$") {
                            $branches += $Matches['branch'].Trim().Trim("'", '"')
                        }
                    }
                }
                break
            }
        }
    }

    return @($branches | Where-Object { $_ -ne '' } | Sort-Object -Unique)
}

$files = Get-WorkflowFiles -InputPath $Path
if (-not $files) {
    Write-Output "No GitHub workflow files found under '$Path'."
    exit 0
}

$exitCode = 0
$deployJobPattern = '^(deploy|update|release|promote|provision|migrate)'

foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
    $text = $lines -join "`n"
    $findings = @()

    $hasPullRequestTrigger = $text -match '(?m)^\s*pull_request:\s*$'
    $hasWorkflowDispatch = $text -match '(?m)^\s*workflow_dispatch:\s*$'
    $pushBranches = Get-PushBranches -Lines $lines
    $allowedBranches = if ($pushBranches.Count -gt 0) { $pushBranches } else { $DefaultBranches }
    $escapedBranches = @($allowedBranches | ForEach-Object { [regex]::Escape($_) })
    $branchPattern = if ($escapedBranches.Count -gt 0) { $escapedBranches -join '|' } else { 'main|master|trunk' }

    $jobs = Get-Jobs -Lines $lines
    if ($jobs.Count -eq 0) {
        Write-Output "=== $($file.FullName) ==="
        Write-Output "  WARN   No jobs block found."
        Write-Output ""
        continue
    }

    $deployJobsChecked = 0

    foreach ($job in $jobs) {
        $block = $lines[$job.Line..$job.EndLine] -join "`n"
        $isDeployLikeName = $job.Id -match $deployJobPattern
        $hasEnvironment = $block -match "(?m)^\s{$($job.PropCol)}environment:\s*\S"
        $hasAzureDeployCall = $block -match 'az\s+deployment\s+group\s+(validate|create|what-if)'
        $hasAppDeployAction = $block -match 'azure/functions-action|azure/webapps-deploy'
        $isDeployJob = $isDeployLikeName -or $hasEnvironment -or $hasAzureDeployCall -or $hasAppDeployAction

        if (-not $isDeployJob) { continue }
        $deployJobsChecked++

        $conditionLine = $null
        $conditionText = $null
        for ($i = $job.Line + 1; $i -le $job.EndLine; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*#') { continue }
            if ($line -match "^\s{$($job.PropCol)}if:\s*(?<expr>.+)$") {
                $conditionLine = $i + 1
                $conditionText = $Matches['expr'].Trim()
                if ($conditionText -match '^[>|]-?$') {
                    $exprLines = @()
                    for ($k = $i + 1; $k -le $job.EndLine; $k++) {
                        $candidate = $lines[$k]
                        if ($candidate -match '^\s*#') { continue }
                        if ($candidate -match '^\s*$') { continue }
                        $indent = $candidate.Length - $candidate.TrimStart().Length
                        if ($indent -le $job.PropCol) { break }
                        $exprLines += $candidate.Trim()
                    }
                    $conditionText = $exprLines -join ' '
                }
                break
            }
        }

        $jobDisplay = "$($job.Id) (line $($job.Line + 1))"

        if ($null -eq $conditionText) {
            if ($hasPullRequestTrigger) {
                $findings += "ERROR  Deploy job '$jobDisplay' has no job-level if guard. Pull request runs can deploy."
                $exitCode = 1
            } else {
                $findings += "WARN   Deploy job '$jobDisplay' has no job-level if guard."
            }
            continue
        }

        if ($conditionText -notmatch 'github\.event_name') {
            if ($hasPullRequestTrigger) {
                $findings += "ERROR  Deploy job '$jobDisplay' is not gated on github.event_name (if at line $conditionLine). Add github.event_name != 'pull_request'."
                $exitCode = 1
            } else {
                $findings += "WARN   Deploy job '$jobDisplay' does not reference github.event_name (if at line $conditionLine)."
            }
        }
        elseif ($conditionText -notmatch "github\.event_name\s*!=\s*['""]pull_request['""]") {
            $findings += "WARN   Deploy job '$jobDisplay' references github.event_name but not as != 'pull_request' (if at line $conditionLine)."
        }

        $hasLiteralRefGuard = $conditionText -match "github\.ref\s*==\s*['""]refs/heads/($branchPattern)['""]" -or
            $conditionText -match "github\.ref_name\s*==\s*['""]($branchPattern)['""]"
        $hasDefaultBranchGuard = $conditionText -match 'github\.event\.repository\.default_branch'

        if (-not ($hasLiteralRefGuard -or $hasDefaultBranchGuard)) {
            if ($hasWorkflowDispatch) {
                $findings += "WARN   Deploy job '$jobDisplay' has no explicit default-branch guard in its if expression (if at line $conditionLine). workflow_dispatch can deploy non-default branches."
            } else {
                $findings += "INFO   Deploy job '$jobDisplay' has no explicit default-branch guard."
            }
        }
    }

    Write-Output "=== $($file.FullName) ==="
    $blocking = @($findings | Where-Object { $_ -match '^ERROR' })
    if ($deployJobsChecked -eq 0) {
        Write-Output "  INFO   No deploy-like jobs detected."
    }
    elseif ($blocking.Count -eq 0 -and $findings.Count -eq 0) {
        Write-Output "  OK  $deployJobsChecked deploy job(s) checked, all gated against pull request deploys."
    } else {
        $findings | ForEach-Object { Write-Output "  $_" }
    }
    Write-Output ""
}

exit $exitCode
