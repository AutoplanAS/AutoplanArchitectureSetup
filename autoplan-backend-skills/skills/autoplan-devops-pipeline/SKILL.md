---
name: autoplan-devops-pipeline
description: "Azure DevOps YAML pipelines for Autoplan integrations: the five-stage build/dev-infra/dev-app/prod-infra/prod-app pattern with prod gated on a successful dev deploy, separate function-app and infra artifacts, environment approval gates, validate-before-create Bicep deploys, optional config-only redeploy stages, gating deploy stages so pull request validation cannot deploy to production, and running tests so that they actually enforce something. WHEN: \"azure-pipelines.yml\", \"CI pipeline\", \"add a deploy stage\", \"pipeline stage\", \"deploy to prod\", \"build and publish the function\", \"pipeline variables\", \"tests not running in CI\", \"PublishTestResults\", \"artifact\", \"service connection\", \"PR validation\", \"pr trigger\", \"build validation policy\", \"branch policy\", \"validate pull request\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.1.0"
  reference-implementation: EchoesIntegration
---

# Autoplan DevOps Pipeline

One `azure-pipelines.yml` per integration, five stages, `ubuntu-latest`. All six integrations share
the stage structure exactly. Where they differ is testing, and that difference is the point of this
skill.

Reference: `EchoesIntegration/azure-pipelines.yml` (237 lines).

## Rules

1. **Five stages: `Build` -> `DeployDevInfra` -> `DeployDevApp` -> `DeployProdInfra` ->
   `DeployProdApp`.** Prod depends on a successful dev *app* deploy, so nothing reaches production
   that has not run in dev. See [stages.md](references/stages.md).
2. **Build once, deploy that artifact everywhere.** Two artifacts, `function-app` and `infra`. Dev
   and prod deploy the same zip. Never rebuild per environment.
3. **Infra stages are toggleable, app stages are not.** `deployDevInfra` / `deployProdInfra`
   parameters let you skip a no-op infra deploy without skipping the code deploy.
4. **`az deployment group validate` before `az deployment group create`,** with identical
   parameters. All six do this.
5. **Every deploy stage is a `deployment` job with an `environment:`,** which is where approval
   gates attach. A plain `job:` bypasses them silently.
6. **A test step must actually fail the build.** A commented-out test task beside a live
   `PublishTestResults@2` is worse than no test step, because it reports success. See
   [testing-in-ci.md](references/testing-in-ci.md).
7. **Secrets come from secret-flagged pipeline variables, single-quoted at the call site.**
   Unquoted, a connection string containing `;` or a space breaks the command. See
   [secrets-and-variables.md](references/secrets-and-variables.md).
8. **Every `Deploy*` and `Update*Config` stage condition starts with
   `ne(variables['Build.Reason'], 'PullRequest')`.** A Build Validation policy runs the whole
   pipeline against the pull request merge commit, so without this guard, opening a pull request
   deploys it to production. This is also what stops a manual queue on a feature branch from
   reaching prod. See [gaps.md](references/gaps.md) gap 8.
9. **PR validation is a branch policy, never a `pr:` trigger.** The `pr:` key is ignored on Azure
   Repos Git. Use `az repos policy build create`, and only after rule 8 is in place on the target
   branch.

## Current state

Verified 2026-08-19 with `scripts/Check-PipelineTestEnforcement.ps1`:

| Repo | Stages | Tests in CI |
|---|---|---|
| Echoes | 5 | runs, enforced (`failTaskOnFailedTests: true`) |
| HubSpot | 5 | runs, skippable via a queue-time parameter |
| SmartCar | 5 | runs |
| Drive | 7 | **disabled** (test and publish both commented out) |
| OFV | 7 | **disabled** (test and publish both commented out) |
| Easypark | 5 | **disabled, and reports success anyway** |

Easypark is the defect: the test task is commented out at lines 60-64 while `PublishTestResults@2`
still runs at line 66. The build is green and a "Publish test results" step appears in the log.
*(Fixed on branch `joergenamrudhagen-turbo-waffle`, commit `55d7f49`, pending merge.)*

**Deploy gating, verified 2026-08-19 with `scripts/Check-PipelineDeployGating.ps1`:** all six
pipelines had every `Deploy*`/`Update*Config` stage ungated on build reason, and no environment in
the project has an approval check. Fixed across 28 stages on branch
`joergenamrudhagen-turbo-waffle` (Drive `82a3e2b`, Easypark `e363030`, HubSpot `7962bcc`, OFV
`d3eae61`, Echoes `30cdb1f`), pending merge. Until those merge, do **not** create Build Validation
policies — see [gaps.md](references/gaps.md) gap 8.

```powershell
.\scripts\Check-PipelineTestEnforcement.ps1 -Path <repo-or-pipeline.yml>
.\scripts\Check-PipelineDeployGating.ps1 -Path <repo-or-pipeline.yml>
```

## References

- [stages.md](references/stages.md) -- the five stages, their dependencies and conditions, plus the optional config-only stages.
- [testing-in-ci.md](references/testing-in-ci.md) -- `bash` versus `DotNetCoreCLI@2`, when each is correct, and how a test step stops enforcing anything.
- [deployment-steps.md](references/deployment-steps.md) -- the Bicep deploy and function app deploy tasks in full.
- [secrets-and-variables.md](references/secrets-and-variables.md) -- pipeline variables, service connections, quoting.
- [gaps.md](references/gaps.md) -- no PR validation, ungated deploy stages, no what-if, no rollback, no smoke test.

If the repository is deploying from GitHub Actions instead of Azure DevOps, use
`autoplan-github-pipeline`.
