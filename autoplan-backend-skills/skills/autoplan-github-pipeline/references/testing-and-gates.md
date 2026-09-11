# Testing and gates

The same defect class from Azure DevOps exists in GitHub Actions too: workflows that look like
they validate pull requests, while deploy jobs still run.

## Required checks

1. Workflow triggers on `pull_request` for validation.
2. `dotnet test` step is live and blocking.
3. Deploy jobs are gated off pull requests.
4. Prod deploy still depends on dev app deploy.

## Test enforcement

```yaml
- name: Test
  run: dotnet test <Integration>.Tests/<Integration>.Tests.csproj --configuration Release
```

Not allowed:

- `continue-on-error: true` on a test step.
- `dotnet test ... || true`.
- Removing tests on PR events while keeping deploy jobs active.

## Deploy gating

Minimum safe guard:

```yaml
if: >-
  github.event_name != 'pull_request' &&
  github.ref == 'refs/heads/main'
```

If `workflow_dispatch` exists, keep branch guard in place so manual runs from feature branches do
not deploy.

## Verification scripts

```powershell
.\scripts\Check-GitHubWorkflowTestEnforcement.ps1 -Path <repo-or-workflow.yml>
.\scripts\Check-GitHubWorkflowDeployGating.ps1 -Path <repo-or-workflow.yml>
```

For non-standard default branches, pass them explicitly:

```powershell
.\scripts\Check-GitHubWorkflowDeployGating.ps1 -Path <repo-or-workflow.yml> -DefaultBranches trunk,develop
```

Both scripts are static checks over workflow YAML. They are designed to catch silent unsafe edits
before merge.
