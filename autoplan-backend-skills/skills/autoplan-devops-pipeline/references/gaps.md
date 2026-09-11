# Gaps

What the pipelines do **not** do. Verified across all six `azure-pipelines.yml` files, 2026-08-19.

## 1. No PR validation

Every pipeline triggers on a single long-lived branch and nothing else:

```yaml
trigger:
  branches:
    include:
      - main        # OFV uses master
```

**No pipeline validates a pull request.** Nothing builds or tests a branch before it lands. A branch
is validated for the first time after it is merged, at which point a failure is already on the
default branch and the pipeline is trying to deploy it to dev.

This compounds with the testing gaps: on the three repos where tests do not run at all, a
regression's first opportunity to be noticed is in production behaviour.

### Do not reach for a `pr:` trigger

The obvious fix does not work here, and it fails silently:

```yaml
pr:            # ignored on Azure Repos Git — do not use
  branches:
    include:
      - main
```

Microsoft's documentation is explicit that for Azure Repos Git, PR trigger functionality "is
implemented using branch policies". The `pr:` key is honoured for GitHub and Bitbucket, **not** for
Azure Repos. Committing it produces a green diff, no error, and no validation — the worst outcome,
because it looks solved.

The real control is a **Build Validation branch policy** on the target branch:

```powershell
az repos policy build create --org $org --project $proj `
  --repository-id $repoId --branch main --build-definition-id $defId `
  --display-name 'PR validation - <pipeline>' `
  --blocking true --enabled true `
  --manual-queue-only false --queue-on-source-update-only true `
  --valid-duration 720
```

Two behaviours to know: draft pull requests do not trigger a policy build, and creating the policy
requires project administrator rights.

### Prerequisite: gate the deploy stages first

**Do not create these policies before fixing gap 8.** A validation build runs the pipeline against
the *merge commit*, all stages included. With deploy stages ungated, opening a pull request deploys
it to production.

Also check the target branch actually exists. Drive and SmartCar trigger on `main` while the Drive
repository's default branch is `master`, so their CI has never fired — every run in their history is
a manual queue.

## 2. No `what-if` before an infra deploy

`az deployment group validate` confirms the template compiles and the parameters resolve. It does
not say what will change.

`az deployment group what-if` shows the resource-level diff -- what will be created, modified or
**deleted**. Nothing uses it. For a prod infra deploy, this is the difference between knowing you
are about to replace a storage account and finding out afterwards.

```bash
az deployment group what-if \
  --resource-group rg-echoes-prod \
  --template-file $(Pipeline.Workspace)/infra/main.bicep \
  --parameters $(Pipeline.Workspace)/infra/parameters.prod.bicepparam \
  --parameters ...
```

Adding it to the prod infra stage, before `create`, costs one call.

## 3. No smoke test after deploy

The pipeline reports success when `AzureFunctionApp@2` finishes uploading. Nothing confirms the app
starts, that its configuration binds, or that a function is registered.

A Function App with a missing app setting deploys perfectly and then fails at its first timer fire,
hours later, with nothing watching. There is no HTTP health endpoint on any integration and no
post-deploy verification step.

Minimum viable version, appended to each app stage:

```bash
az functionapp function list \
  --name echoes-dev-func \
  --resource-group rg-echoes-dev \
  --query "length(@)"
```

A result of `0` means the deploy produced no runnable functions -- the single most common
silent-failure mode.

## 4. No rollback

No stage redeploys a previous artifact, and no deployment strategy other than `runOnce` is used
(no `canary`, no `rolling`). Recovery from a bad prod deploy is: find the last good build in the
Azure DevOps UI, and re-run its `DeployProdApp` stage by hand.

That works because artifacts are retained and the app deploy is idempotent. It is worth knowing it
is the plan, because nothing writes it down.

## 5. Prod is gated on a dev *deploy*, not on dev *working*

`DeployProdInfra` depends on `DeployDevApp` succeeding. `DeployDevApp` succeeds when the zip
uploads. So the gate confirms "the artifact deployed to dev without erroring", not "the integration
works in dev".

Given no smoke test (3) and no health endpoint, a build that is broken at runtime passes the gate
and proceeds to production in the same run. An environment approval on `<integration>-prod` would be
the only thing standing between the two -- and **none is configured on any environment in this
project** (verified 2026-08-19). Nothing stands between them today.

## 6. Half the estate does not run tests

Covered in full in [testing-in-ci.md](testing-in-ci.md). Summary: Drive, OFV and Easypark do not run
tests; Easypark additionally reports that it does.

## 7. No static analysis, no dependency scanning, no linting

No `dotnet format --verify-no-changes`, no analyzer enforcement step, no vulnerable-package scan
(`dotnet list package --vulnerable`), no secret scanning.

The last one is pointed: `OFVIntegration/local.settings.json` is committed with live credentials,
and a secret-scanning step in CI would have caught it at the commit that introduced it. See
`autoplan-integration-auth/references/secrets-management.md`.

```bash
dotnet list package --vulnerable --include-transitive
```

is one line and fails loudly on a known CVE.

## 8. Deploy stages are not gated on build reason

⛔ **This is the highest-severity gap in this document, and it is a live production risk today —
not only a blocker for PR validation.**

Every stage's condition tests the deploy parameters and the preceding stage's result. None tests the
branch or the build reason, and both parameters default to `true`:

```yaml
parameters:
  - name: deployDevInfra
    default: true          # both default true
  - name: deployProdInfra
    default: true

- stage: DeployProdApp
  condition: and(succeeded('DeployDevApp'), or(eq(${{ parameters.deployProdInfra }}, false), ...))
```

So any successful build runs `Build → DeployDevApp → DeployProdApp` through to production. Two
consequences:

- Manually queueing a pipeline on **any** branch deploys that branch to production.
- Adding a Build Validation policy would deploy **every pull request** to production, because a
  validation build runs the whole YAML against the merge commit.

There is no safety net at the environment layer either. All twelve environments — including all six
`-prod` ones — were verified to have **zero approval checks** configured.

The fix is one condition per stage, applied to every `Deploy*` and `Update*Config` stage:

```yaml
condition: and(ne(variables['Build.Reason'], 'PullRequest'), succeeded('Build'), ...)
```

`Build.Reason` is `PullRequest` only for validation builds, so CI, manual and scheduled runs are
completely unaffected. Prefer this over a branch check: it is the narrowest guard that makes PR
validation safe, and it does not have to be revisited when a default branch is renamed.

Verify with `scripts/Check-PipelineDeployGating.ps1`.

## Priority

In order of value per unit of effort:

1. **Gate deploy stages on `Build.Reason`** (8) -- a live production risk, and a hard prerequisite
   for anything below it.
2. **PR validation via branch policy** (1) -- catches everything else earlier. Only after 8.
3. **Re-enable tests** (6) -- the work already exists and is switched off.
4. **Post-deploy smoke test** (3) -- closes the gap that lets a broken build reach prod.
5. **`what-if` on prod infra** (2).
6. **Vulnerable-package scan** (7).
