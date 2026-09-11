# Deployment steps

## Build and publish artifacts

```yaml
- name: Publish function app
  run: dotnet publish src/<Integration>.csproj -c Release -o out/function-app --no-build

- name: Zip function app
  run: |
    cd out/function-app
    zip -r ../function-app.zip .

- uses: actions/upload-artifact@v4
  with:
    name: function-app
    path: out/function-app.zip

- uses: actions/upload-artifact@v4
  with:
    name: infra
    path: infra/
```

Build once, then deploy those exact artifacts in every environment.

## Azure login with OIDC

```yaml
permissions:
  contents: read
  id-token: write

- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

Do not use a long-lived `AZURE_CREDENTIALS` secret unless migration constraints force it.

## Bicep deployment pattern

```yaml
- name: Validate template
  run: |
    az group create --name rg-<integration>-dev --location norwayeast
    az deployment group validate \
      --resource-group rg-<integration>-dev \
      --template-file infra/main.bicep \
      --parameters infra/parameters.dev.bicepparam \
      --parameters apiKey='${{ secrets.API_KEY }}'

- name: Deploy template
  run: |
    az deployment group create \
      --resource-group rg-<integration>-dev \
      --template-file infra/main.bicep \
      --parameters infra/parameters.dev.bicepparam \
      --parameters apiKey='${{ secrets.API_KEY }}'
```

The `validate` and `create` parameter lists must stay identical.

## Function app deploy

```yaml
- uses: actions/download-artifact@v4
  with:
    name: function-app
    path: out

- uses: azure/functions-action@v1
  with:
    app-name: <integration>-dev-func
    package: out/function-app.zip
```

Keep app names aligned with the Bicep naming convention.
