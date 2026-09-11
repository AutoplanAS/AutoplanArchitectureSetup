# Secrets and environments

## Where values come from in GitHub Actions

| Kind | Source | Example |
|---|---|---|
| Non-secret config | repository/environment variable (`vars`) | `vars.AZURE_REGION` |
| Secret config | environment or repository secret (`secrets`) | `secrets.ECHOES_API_KEY` |
| Azure auth | OIDC-backed Entra app secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) | `azure/login@v2` |

Rule: secrets never live in workflow YAML, `.bicepparam`, or source-controlled local config.

## Environment boundaries

Use GitHub environments to separate dev/prod values:

- `dev` environment secrets: dev API keys, dev account IDs.
- `prod` environment secrets: prod keys only.
- `prod` protection: required reviewers enabled.

Each deploy job sets `environment: dev` or `environment: prod`. That is what scopes secrets and
enforcement.

## Passing secrets to Bicep safely

```yaml
--parameters echoesApiKey='${{ secrets.ECHOES_API_KEY }}'
```

Quote every substituted value to protect whitespace and special characters in connection strings.

## OIDC requirements

GitHub workflow side:

```yaml
permissions:
  id-token: write
  contents: read
```

Azure side:

1. One Entra app (or managed identity-backed app registration) per repo/environment boundary.
2. Federated credential that trusts the repo and branch/environment constraints.
3. Contributor role on the deployment scope (resource group or subscription).

If OIDC is not configured, deployments fail at login time. Do not bypass by embedding static
service principal secrets as a permanent fallback.
