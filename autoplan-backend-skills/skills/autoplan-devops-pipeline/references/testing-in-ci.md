# Testing in CI

This is the one part of the pipeline where the estate genuinely disagrees with itself, and where
the disagreement has already cost something.

## Current state

Measured with `scripts/Check-PipelineTestEnforcement.ps1`, 2026-08-19:

| Repo | Test step | PublishTestResults | Verdict |
|---|---|---|---|
| Echoes | `bash: dotnet test` (live) | live, `failTaskOnFailedTests: true` | correct |
| HubSpot | `DotNetCoreCLI@2` (live, gated) | live, gated | runs, but skippable at queue time |
| SmartCar | `DotNetCoreCLI@2` (live) | live | runs |
| Drive | commented out (72-76) | commented out (78-84) | tests do not run |
| OFV | commented out (66-70) | commented out (72-78) | tests do not run |
| Easypark | commented out (60-64) | **live (66)** | **tests do not run, build reports otherwise** |

**Half the estate does not run its tests in CI.** Drive and OFV are at least honest about it --
they commented out the publish step too. Easypark is the defect.

## The Easypark defect

`EasyparkIntegration/EasyparkIntegration/azure-pipelines.yml`:

```yaml
          #- task: DotNetCoreCLI@2
          #  displayName: 'Test'
          #  inputs:
          #    command: 'test'
          #    projects: '$(testProjectPath)'
          #    arguments: '--configuration $(buildConfiguration) --logger trx --results-directory $(Agent.TempDirectory)/TestResults'

          - task: PublishTestResults@2
            displayName: 'Publish test results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'VSTest'
              testResultsFiles: '$(Agent.TempDirectory)/TestResults/*.trx'
              testRunTitle: 'EasyparkIntegration Tests'
```

No `.trx` file is ever produced. `PublishTestResults@2` finds nothing to publish, which by default
is a **warning, not a failure**. The build is green, the log contains a step called "Publish test
results", and the Tests tab is empty in a way nobody looks at.

The repo has ten test files including `BillingRecordStorageServiceTests.cs`. They pass locally and
have never gated a deployment.

**Rule: if you disable a test step, disable its publish step in the same commit.** A reporting step
with no producer is a lie the pipeline tells you every run.

## `bash` versus `DotNetCoreCLI@2`

Echoes is the only repo using a raw bash step, and it documents why:

```yaml
# NOTE: The Functions Worker SDK restores a generated WorkerExtensions
# project during the *build* phase. The DotNetCoreCLI@2 'test' command
# does not supply the NuGet config that its 'restore' command injects,
# which makes that inner restore fail on clean Linux agents. Running
# dotnet test from a plain bash step (with the repo NuGet.config)
# avoids this known issue:
# https://github.com/Azure/azure-functions-dotnet-worker/issues/1888
- bash: |
    dotnet test "$(testProjectPath)" \
      --configuration $(buildConfiguration) \
      --logger trx \
      --results-directory "$(Agent.TempDirectory)/TestResults"
  displayName: 'Test'
```

**This is conditional advice, not a blanket rule.** Echoes is also the only repo with a
repo-level `NuGet.config` -- verified: the only two `NuGet.config` files in the estate are Echoes'
and the template in `autoplan-integration-scaffold`. The problem the comment describes is
`DotNetCoreCLI@2` injecting its own NuGet configuration and thereby losing the repo's. With no
repo-level `NuGet.config` there is nothing to lose, which is why SmartCar and HubSpot run
`DotNetCoreCLI@2 test` successfully.

So:

| Situation | Use |
|---|---|
| Repo has its own `NuGet.config` (private feed, source mapping) | `bash: dotnet test` |
| Repo uses only nuget.org defaults | either; `DotNetCoreCLI@2` is fine |

If you are unsure, `bash` is the safe default: it behaves identically to a local run and has no
hidden injection.

## Publishing results

```yaml
- task: PublishTestResults@2
  displayName: 'Publish test results'
  condition: succeededOrFailed()
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '$(Agent.TempDirectory)/TestResults/**/*.trx'
    testRunTitle: 'EchoesIntegration Tests'
    failTaskOnFailedTests: true
```

- **`condition: succeededOrFailed()`** -- results are most valuable when the tests failed. Without
  it the step is skipped exactly when you need it.
- **`**/*.trx`, not `*.trx`.** Echoes uses the recursive glob; the other five use the single-level
  form. `dotnet test --results-directory X` writes directly into `X` today, so both work -- until a
  second test project or a runner change nests the output, at which point the single-level form
  silently publishes nothing. Use `**/*.trx`.
- **`failTaskOnFailedTests: true`** -- set only by Echoes. The runner step already fails the build
  on a failing test, so this is a second guard rather than the primary one. It matters if the
  runner step is ever given `continueOnError: true`.

## Gating tests behind a parameter

HubSpot allows tests to be skipped at queue time:

```yaml
parameters:
  - name: skipTestRun
    type: boolean
    default: false

# ...
- task: DotNetCoreCLI@2
  displayName: 'Test'
  condition: eq(${{ parameters.skipTestRun }}, false)
```

The default is correct, and an explicit opt-out chosen by a human at queue time is far better than
a commented-out task. But it is still a switch that turns off the only automated check on a repo
whose deals sync is currently broken (see
`autoplan-sql-model-alignment/references/known-defects.md`). Prefer no switch.

## The rule

A test step is only worth having if a failing test stops a deployment. Concretely:

1. The test step is live.
2. `PublishTestResults@2` is live, with `condition: succeededOrFailed()` and
   `failTaskOnFailedTests: true`.
3. Neither is gated on a parameter that defaults to skipping.
4. The deploy stages depend on `Build`.

Point 4 holds everywhere already, which is what makes points 1-3 worth enforcing: the moment tests
run, they gate production.
