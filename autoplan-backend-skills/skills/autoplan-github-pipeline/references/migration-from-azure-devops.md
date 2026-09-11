# Migration from Azure DevOps pipeline

This skill keeps the Autoplan release semantics and swaps only the CI/CD platform.

## Concept mapping

| Azure DevOps | GitHub Actions |
|---|---|
| `azure-pipelines.yml` stages | workflow jobs with `needs` |
| pipeline variables (secret) | repository/environment secrets |
| pipeline variables (plain) | `vars` |
| `deployment` job with `environment:` | job with `environment:` |
| environment approval checks | GitHub environment required reviewers |
| `AzureCLI@2` | `azure/login@v2` + `run: az ...` |
| `AzureFunctionApp@2` | `azure/functions-action@v1` |
| build artifacts | `upload-artifact` / `download-artifact` |
| build validation branch policy | `pull_request` workflow trigger + required status checks |

## Guard translation

Azure DevOps:

```yaml
condition: and(ne(variables['Build.Reason'], 'PullRequest'), ...)
```

GitHub Actions:

```yaml
if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
```

## Migration sequence

1. Keep `infra/main.bicep` and `.bicepparam` unchanged.
2. Create workflow from `references/templates/deploy.yml`.
3. Configure GitHub environments (`dev`, `prod`) and secrets.
4. Configure OIDC trust and role assignments in Azure.
5. Run both check scripts against the new workflow.
6. Keep Azure DevOps pipeline in place until GitHub deploy path is proven.

## Cutover criteria

Use GitHub as system of record only after:

1. PR validation blocks merges on failed build/test.
2. Dev deploy succeeds from `main`.
3. Prod deploy requires reviewer approval.
4. Roll-forward and rollback runbooks are documented.
