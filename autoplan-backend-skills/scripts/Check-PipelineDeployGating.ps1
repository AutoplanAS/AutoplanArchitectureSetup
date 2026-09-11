# Checks that every deploy stage in an Azure DevOps pipeline is gated on build reason.
#
# The specific failure this exists to catch: a Build Validation branch policy runs the
# whole pipeline against the pull request merge commit. If the deploy stages are gated
# only on parameters that default to true, opening a pull request deploys it to
# production. The same gap lets a manual queue on any branch reach prod.
#
# The guard is:
#   condition: and(ne(variables['Build.Reason'], 'PullRequest'), ...)
#
# Usage:
#   .\Check-PipelineDeployGating.ps1 -Path <pipeline.yml or repo root>

param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Path -PathType Container) {
    # -Include is silently ignored when it is combined with -LiteralPath, which makes
    # Get-ChildItem return every file in the tree instead of just the pipelines. Filter
    # on the name instead, and skip build output so binaries are never opened as text.
    $files = @(
        Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in '.yml', '.yaml' -and
                $_.Name -like '*azure-pipelines*' -and
                $_.FullName -notmatch '[\\/](obj|bin|node_modules|\.git)[\\/]'
            }
    )
} else {
    $files = @(Get-Item -LiteralPath $Path)
}

if (-not $files) {
    Write-Output "No pipeline files found under '$Path'."
    exit 0
}

$exitCode = 0

# Stages that perform a deployment or mutate a deployed environment. Build stages are
# expected to run on a pull request -- that is the entire point of validating one.
$deployStagePattern = '^(Deploy|Update|Release|Promote|Provision|Migrate)'

foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
    $findings = @()

    # Collect stage declarations: name, line number, and the indent its properties sit at.
    $stages = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#') { continue }
        if ($lines[$i] -match '^(?<indent>\s*)-\s*stage:\s*(?<name>\S+)') {
            $stages += [pscustomobject]@{
                Name     = $Matches['name']
                Line     = $i
                PropCol  = $Matches['indent'].Length + 2
            }
        }
    }

    $deployStageCount = 0
    for ($s = 0; $s -lt $stages.Count; $s++) {
        $stage = $stages[$s]
        if ($stage.Name -notmatch $deployStagePattern) { continue }
        $deployStageCount++

        $end = if ($s + 1 -lt $stages.Count) { $stages[$s + 1].Line - 1 } else { $lines.Count - 1 }

        # A stage-level condition sits exactly one level in from the "- stage:" marker.
        # Anything deeper belongs to a job or a step and does not gate the stage.
        $conditionLine = $null
        $conditionText = $null
        for ($i = $stage.Line + 1; $i -le $end; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*#') { continue }
            if ($line -match "^\s{$($stage.PropCol)}condition:\s*(?<expr>.+)$") {
                $conditionLine = $i + 1
                $conditionText = $Matches['expr']
                break
            }
        }

        $displayName = "$($stage.Name) (line $($stage.Line + 1))"

        if ($null -eq $conditionText) {
            $findings += "ERROR  Stage '$displayName' has no stage-level condition, so it runs on every build including pull request validation. Add ne(variables['Build.Reason'], 'PullRequest')."
            $exitCode = 1
        }
        elseif ($conditionText -notmatch "Build\.Reason") {
            $findings += "ERROR  Stage '$displayName' is not gated on build reason (condition at line $conditionLine). A pull request validation build would deploy. Add ne(variables['Build.Reason'], 'PullRequest') as the first argument."
            $exitCode = 1
        }
        elseif ($conditionText -notmatch "ne\(\s*variables\['Build\.Reason'\]\s*,\s*'PullRequest'\s*\)") {
            $findings += "WARN   Stage '$displayName' mentions Build.Reason at line $conditionLine but not as ne(variables['Build.Reason'], 'PullRequest'). Confirm the expression excludes validation builds."
        }
    }

    $text = $lines -join "`n"

    # A pr: trigger is honoured for GitHub and Bitbucket but ignored for Azure Repos Git,
    # where PR validation is a branch policy. Committing one looks like a fix and is not.
    if ($text -match "(?m)^pr:") {
        $findings += "WARN   A top-level 'pr:' trigger is declared. This is ignored for Azure Repos Git repositories -- PR validation there is a Build Validation branch policy (az repos policy build create). If this repo is on Azure Repos, the trigger does nothing."
    }

    if ($text -match "(?m)^\s*-\s*name:\s*deploy\w*\s*$") {
        $defaults = [regex]::Matches($text, "(?ms)-\s*name:\s*(deploy\w+).*?default:\s*(true|false)")
        $trueDefaults = @($defaults | Where-Object { $_.Groups[2].Value -eq 'true' } | ForEach-Object { $_.Groups[1].Value })
        if ($trueDefaults.Count -gt 0) {
            $findings += "INFO   Deploy parameters default to true ($($trueDefaults -join ', ')), so a run deploys unless someone opts out at queue time."
        }
    }

    Write-Output "=== $($file.FullName) ==="
    $blocking = @($findings | Where-Object { $_ -match '^(ERROR|WARN)' })
    if ($blocking.Count -eq 0) {
        Write-Output "  OK  $deployStageCount deploy stage(s) checked, all gated against pull request validation builds."
    }
    if ($findings.Count -gt 0) {
        $findings | ForEach-Object { Write-Output "  $_" }
    }
    Write-Output ""
}

exit $exitCode
