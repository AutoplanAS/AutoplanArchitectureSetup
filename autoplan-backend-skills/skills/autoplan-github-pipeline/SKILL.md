---
name: autoplan-github-pipeline
description: "GitHub Actions deployment workflows for Autoplan integrations: five-job build/dev-infra/dev-app/prod-infra/prod-app flow, environment protection rules, OIDC Azure login, artifact reuse across environments, validate-before-create Bicep deploys, pull-request-safe deploy gating, and test enforcement. WHEN: \"github actions\", \".github/workflows\", \"deploy from github\", \"workflow yml\", \"azure/login\", \"oidc\", \"github environments\", \"pull request validation\", \"workflow_dispatch\", \"migrate from azure devops pipeline\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  derived-from: autoplan-devops-pipeline + autoplan-azure-deploy
---

# Autoplan GitHub pipeline

One workflow per integration, five deployment jobs, same release flow as the Azure DevOps pattern:

`build -> deploy-dev-infra -> deploy-dev-app -> deploy-prod-infra -> deploy-prod-app`

The platform changed, the guard rails did not.

## Rules

1. **Build once, deploy the same artifacts everywhere.** Upload `function-app` and `infra` once in `build`; every deploy job downloads those artifacts.
2. **Keep pull request validation and deployment in the same workflow, but gate deploy jobs.** Each deploy job has:
   - `if: github.event_name != 'pull_request'`
   - branch guard (`github.ref == 'refs/heads/main'` or your default branch)
3. **Prod depends on successful dev app deploy.** `deploy-prod-infra` needs `deploy-dev-app`, and `deploy-prod-app` needs `deploy-prod-infra` plus the same infra-toggle logic.
4. **Use GitHub Environments (`dev`, `prod`) on deploy jobs.** Required reviewers and environment-scoped secrets belong there, not in YAML.
5. **Use OIDC (`azure/login@v2`) instead of stored Azure credentials.** Configure `permissions: id-token: write` and federated credentials in Entra ID.
6. **Run `az deployment group validate` before `az deployment group create`, with byte-identical parameters.** Validate a different parameter set and you validated nothing.
7. **Tests must fail the run.** No `continue-on-error` on test steps, and no `dotnet test ... || true`.
8. **Use `workflow_dispatch` inputs for infra toggles.** App deploy is never optional on a normal release run.

## What this depends on

- **Infrastructure shape:** `autoplan-azure-deploy`
- **GitHub workflow rules:** this skill
- **Legacy Azure DevOps migration:** `references/migration-from-azure-devops.md`

Use checks before merging:

```powershell
.\scripts\Check-GitHubWorkflowDeployGating.ps1 -Path <repo-or-workflow.yml>
.\scripts\Check-GitHubWorkflowTestEnforcement.ps1 -Path <repo-or-workflow.yml>
```

## References

- [workflow-shape.md](references/workflow-shape.md) -- the five-job layout and dependencies.
- [deployment-steps.md](references/deployment-steps.md) -- build artifacts, Azure login, Bicep and app deploy steps.
- [secrets-and-environments.md](references/secrets-and-environments.md) -- GitHub environments, secrets, vars, and OIDC.
- [testing-and-gates.md](references/testing-and-gates.md) -- PR-safe deploy guards and test enforcement.
- [migration-from-azure-devops.md](references/migration-from-azure-devops.md) -- one-to-one mapping from Azure DevOps concepts.
- [templates/deploy.yml](references/templates/deploy.yml) -- copy-ready workflow baseline.
