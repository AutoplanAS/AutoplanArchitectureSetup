# Checks an Azure DevOps pipeline for test steps that do not actually enforce anything.
#
# The specific failure this exists to catch: a commented-out test task sitting beside a
# live PublishTestResults task. The pipeline is green, a "Publish test results" step
# appears in the log, and nothing ran.
#
# Usage:
#   .\Check-PipelineTestEnforcement.ps1 -Path <pipeline.yml or repo root>

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

foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
    $findings = @()

    # A line is "commented" if its first non-whitespace character is #.
    $isComment = { param($l) $l -match '^\s*#' }

    $liveTest = @()
    $deadTest = @()
    $livePublish = @()
    $deadPublish = @()

    # A commented line mentioning "dotnet test" may be a disabled task or merely prose
    # explaining why the live step is written the way it is. Echoes has exactly such a
    # comment. Distinguish them structurally: a disabled YAML task keeps its surrounding
    # keys ("- task:", "displayName:", "inputs:", "- bash:") commented out alongside it,
    # and prose never does.
    $structuralNeighbour = {
        param($index)
        $from = [Math]::Max(0, $index - 6)
        $to = [Math]::Min($lines.Count - 1, $index + 6)
        foreach ($candidate in $lines[$from..$to]) {
            if ($candidate -match '^\s*#\s*-?\s*(task|displayName|inputs|bash|script):') { return $true }
        }
        return $false
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $n = $i + 1
        $commented = & $isComment $line

        # A DotNetCoreCLI@2 test command. "command: 'test'" never appears in prose,
        # so it needs no further disambiguation.
        if ($line -match "command:\s*'test'") {
            if ($commented) { $deadTest += $n } else { $liveTest += $n }
        }
        # A raw "dotnet test" invocation.
        elseif ($line -match '\bdotnet\s+test\b') {
            if (-not $commented) {
                $liveTest += $n
            } elseif (& $structuralNeighbour $i) {
                $deadTest += $n
            }
        }

        if ($line -match 'PublishTestResults@2') {
            if ($commented) { $deadPublish += $n } else { $livePublish += $n }
        }
    }

    $text = $lines -join "`n"
    $declaresTestProject = $text -match 'testProjectPath|\.Tests\.csproj'

    if ($deadTest.Count -gt 0 -and $livePublish.Count -gt 0) {
        $findings += "ERROR  Test step is commented out (line(s) $($deadTest -join ', ')) but PublishTestResults@2 is live (line(s) $($livePublish -join ', ')). The pipeline reports a test step that executed nothing."
        $exitCode = 1
    } elseif ($deadTest.Count -gt 0 -and $liveTest.Count -eq 0) {
        $findings += "WARN   Test step is commented out (line(s) $($deadTest -join ', ')) and no live test step remains. Tests do not run in CI."
    }

    if ($liveTest.Count -eq 0 -and $deadTest.Count -eq 0 -and $declaresTestProject) {
        $findings += "WARN   A test project is referenced but no test step exists. Tests do not run in CI."
    }

    if ($liveTest.Count -gt 0 -and $livePublish.Count -gt 0) {
        if ($text -notmatch '(?m)^\s*failTaskOnFailedTests:\s*true') {
            $findings += "INFO   PublishTestResults@2 does not set 'failTaskOnFailedTests: true'. The runner step still fails the build on a failing test, but the guard is missing if that step is ever made non-blocking."
        }
    }

    # A test step gated on a pipeline parameter can be switched off at queue time.
    foreach ($n in $liveTest) {
        $window = $lines[([Math]::Max(0, $n - 6))..([Math]::Min($lines.Count - 1, $n + 1))] -join "`n"
        if ($window -match 'condition:.*parameters\.') {
            $findings += "INFO   Test step at line $n is gated on a pipeline parameter and can be skipped at queue time."
            break
        }
    }

    if ($deadPublish.Count -gt 0 -and $deadTest.Count -gt 0) {
        $findings += "INFO   Both the test step and PublishTestResults are commented out. Tests do not run, but the pipeline does not claim they do."
    }

    Write-Output "=== $($file.FullName) ==="
    if ($findings.Count -eq 0) {
        Write-Output "  OK  Tests run and are enforced."
    } else {
        $findings | ForEach-Object { Write-Output "  $_" }
    }
    Write-Output ""
}

exit $exitCode
