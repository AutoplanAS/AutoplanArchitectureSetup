# Checks GitHub Actions workflows for test steps that do not enforce anything.
#
# Usage:
#   .\Check-GitHubWorkflowTestEnforcement.ps1 -Path <repo root or workflow.yml>

param(
    [Parameter(Mandatory = $true)][string]$Path
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
                    Id      = $Matches['id']
                    Line    = $i
                    Indent  = $indent
                    PropCol = $indent + 2
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

function Get-Needs {
    param(
        [string[]]$Lines,
        [int]$StartLine,
        [int]$EndLine,
        [int]$PropCol
    )

    $needs = @()
    for ($i = $StartLine + 1; $i -le $EndLine; $i++) {
        if ($Lines[$i] -match '^\s*#') { continue }
        if ($Lines[$i] -match "^\s{$PropCol}needs:\s*(?<value>.*)$") {
            $value = $Matches['value'].Trim()
            if ($value) {
                $value = $value.Trim('[', ']')
                $needs += @(
                    $value -split ',' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ -ne '' }
                )
                break
            }

            for ($k = $i + 1; $k -le $EndLine; $k++) {
                if ($Lines[$k] -match '^\s*#' -or $Lines[$k] -match '^\s*$') { continue }
                if ($Lines[$k] -match "^\s{$($PropCol + 2)}-\s*(?<id>[A-Za-z0-9_-]+)\s*$") {
                    $needs += $Matches['id']
                    continue
                }

                if ($Lines[$k] -match "^\s{$PropCol}[A-Za-z0-9_-]+:\s*") { break }
                if (($Lines[$k].Length - $Lines[$k].TrimStart().Length) -le $PropCol) { break }
            }
            break
        }
    }

    return @($needs | Sort-Object -Unique)
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
    $looksDotNet = ($text -match '\bdotnet\b') -or ($text -match '\.csproj')

    $isComment = { param($l) $l -match '^\s*#' }
    $structuralNeighbour = {
        param($index)
        $from = [Math]::Max(0, $index - 6)
        $to = [Math]::Min($lines.Count - 1, $index + 6)
        foreach ($candidate in $lines[$from..$to]) {
            if ($candidate -match '^\s*#\s*-?\s*(name|run|uses|with|continue-on-error):') { return $true }
        }
        return $false
    }

    $liveTests = @()
    $deadTests = @()
    $unsafeTests = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1
        $commented = & $isComment $line

        if ($line -match '\bdotnet\s+test\b') {
            if ($commented) {
                if (& $structuralNeighbour $i) {
                    $deadTests += $lineNo
                }
                continue
            }

            $liveTests += $lineNo

            if ($line -match '\|\|\s*true\b') {
                $unsafeTests += $lineNo
            }

            $windowStart = [Math]::Max(0, $i - 6)
            $windowEnd = [Math]::Min($lines.Count - 1, $i + 6)
            $window = $lines[$windowStart..$windowEnd] -join "`n"
            if ($window -match '(?m)^\s*continue-on-error:\s*true\s*$') {
                $unsafeTests += $lineNo
            }
        }
    }

    $jobs = Get-Jobs -Lines $lines
    $deployJobs = @()
    if ($jobs.Count -gt 0) {
        foreach ($job in $jobs) {
            $block = $lines[$job.Line..$job.EndLine] -join "`n"
            $isDeployLikeName = $job.Id -match $deployJobPattern
            $hasEnvironment = $block -match "(?m)^\s{$($job.PropCol)}environment:\s*\S"
            $hasAzureDeployCall = $block -match 'az\s+deployment\s+group\s+(validate|create|what-if)'
            $hasAppDeployAction = $block -match 'azure/functions-action|azure/webapps-deploy'
            if ($isDeployLikeName -or $hasEnvironment -or $hasAzureDeployCall -or $hasAppDeployAction) {
                $deployJobs += $job
            }
        }
    }

    if ($liveTests.Count -eq 0 -and $deadTests.Count -gt 0 -and $deployJobs.Count -gt 0) {
        $findings += "ERROR  Test steps are commented out (line(s) $($deadTests -join ', ')) and deploy jobs exist."
        $exitCode = 1
    }
    elseif ($liveTests.Count -eq 0 -and $deployJobs.Count -gt 0) {
        $findings += "ERROR  No live dotnet test step found, but deploy jobs exist."
        $exitCode = 1
    }
    elseif ($liveTests.Count -eq 0 -and $hasPullRequestTrigger -and $looksDotNet) {
        $findings += "WARN   Workflow has pull_request trigger but no live dotnet test step."
    }

    if ($unsafeTests.Count -gt 0) {
        $findings += "ERROR  Test enforcement disabled near line(s) $(@($unsafeTests | Sort-Object -Unique) -join ', ') (continue-on-error or '|| true')."
        $exitCode = 1
    }

    foreach ($job in $deployJobs) {
        $needs = Get-Needs -Lines $lines -StartLine $job.Line -EndLine $job.EndLine -PropCol $job.PropCol
        if ($needs.Count -eq 0) {
            $findings += "WARN   Deploy job '$($job.Id)' (line $($job.Line + 1)) has no needs dependency."
        }
    }

    Write-Output "=== $($file.FullName) ==="
    $blocking = @($findings | Where-Object { $_ -match '^ERROR' })
    if ($blocking.Count -eq 0 -and $findings.Count -eq 0) {
        Write-Output "  OK  Test steps are present and blocking."
    } else {
        $findings | ForEach-Object { Write-Output "  $_" }
    }
    Write-Output ""
}

exit $exitCode
