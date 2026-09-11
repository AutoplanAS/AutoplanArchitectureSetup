# Workflow shape

The GitHub Actions release flow keeps the same deployment semantics as the Azure DevOps five-stage
pipeline:

```
build -> deploy-dev-infra -> deploy-dev-app -> deploy-prod-infra -> deploy-prod-app
```

## Trigger model

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      deployDevInfra:
        type: boolean
        default: true
      deployProdInfra:
        type: boolean
        default: true
```

- `pull_request` runs build + tests only.
- `push` to `main` runs full deploy flow.
- `workflow_dispatch` is for controlled manual runs.

## Job dependencies

```yaml
jobs:
  build: {}
  deploy-dev-infra:
    needs: build
  deploy-dev-app:
    needs: [build, deploy-dev-infra]
  deploy-prod-infra:
    needs: deploy-dev-app
  deploy-prod-app:
    needs: [deploy-dev-app, deploy-prod-infra]
```

Prod is gated by successful dev app deploy, not only by successful build.

## Deploy guards

Every deploy job must gate on event and branch:

```yaml
if: >-
  github.event_name != 'pull_request' &&
  github.ref == 'refs/heads/main'
```

For jobs that depend on toggle inputs, include safe fallback for non-dispatch events:

```yaml
if: >-
  github.event_name != 'pull_request' &&
  github.ref == 'refs/heads/main' &&
  (
    github.event_name != 'workflow_dispatch' ||
    inputs.deployDevInfra
  )
```

This avoids null-input behavior on `push` events.

## Environments

Use `environment: dev` and `environment: prod` on deploy jobs so protection rules apply. Required
reviewers belong in GitHub environment settings, not in workflow YAML.
