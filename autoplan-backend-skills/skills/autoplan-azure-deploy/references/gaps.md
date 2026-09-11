# Gaps

What the templates do **not** do. Verified by searching all six `main.bicep` files, 2026-08-19.

## 1. No Key Vault anywhere

**Zero references to Key Vault in any template.** Every secret is passed as a `@secure()` parameter
and written into the Function App's `appSettings` as a literal value.

Consequences:

- A secret is readable in the portal by anyone with Contributor on the Function App.
- Rotation means a redeploy, or an out-of-band `az functionapp config appsettings set` that the next
  infra deploy may revert (see [environments.md](environments.md)).
- There is no audit trail of secret access.
- The same secret is entered separately into each pipeline, because no pipeline uses a variable
  group either.

`@secure()` does the job it claims -- values are masked in deployment history and logs -- but it is
protection in transit and at rest in the *deployment record*, not in the app configuration.

The migration path is a Key Vault reference in the app setting:

```bicep
{
  name: 'Echoes:ApiKey'
  value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/echoes-api-key/)'
}
```

That requires the Function App's `SystemAssigned` identity -- already declared in every template --
to hold **Key Vault Secrets User** on the vault. Which brings us to:

## 2. Managed identity is declared but grants nothing

Every template declares:

```bicep
identity: { type: 'SystemAssigned' }
```

and **no template contains a single role assignment.** There is no
`Microsoft.Authorization/roleAssignments` resource anywhere. The identity exists and can do nothing.

All data access is by connection string with an account key, including
`AzureWebJobsStorage`. Moving storage access to the identity would need
`Storage Table Data Contributor` and `Storage Blob Data Contributor` role assignments plus a
`TableServiceClient(new Uri(...), new DefaultAzureCredential())` in `Program.cs`.

This is the single highest-value hardening available, and the identity is already in place for it.

## 3. SQL is not in the templates

Drive and HubSpot both write to SQL Server. **No template declares a `Microsoft.Sql` resource.**
Both take the connection string as a `@secure()` parameter pointing at a database that exists
outside infrastructure-as-code:

- `DriveFunctions/infra/main.bicep` -- `sqlConnectionString` parameter
- `HubSpotDataRetriever/infra/main.bicep` -- same

So the server, database, firewall rules, and sizing are configured by hand and undocumented in the
repo. The schema is created by application code at runtime (`SalesContractsSqlInitializer`,
`InitializeDatabaseAsync`) rather than by a deployment step -- see
`autoplan-sql-model-alignment/references/schema-scripts.md`. Drive gates that behind a template
parameter, `enableSqlSchemaInitialization bool = false`, which is the closest thing to a schema
deployment step in the estate.

If you are asked "which SQL server does Drive use", the answer is not in the repo.

Two smaller oddities in the same area:

- HubSpot declares a second parameter, `sqlConnectionStringLocal` (line 16), surfaced as the app
  setting `ConnectionStrings:SqlConnectionStringLocal` (line 188). It is `@secure()` and defaults to
  `''`, so it is harmless as deployed -- but a setting named "Local" has no business in a cloud
  template. It is a local-development convenience that leaked into infrastructure. Keep local-only
  configuration in `local.settings.json`.
- Neither template has any way to run a schema migration as part of a deploy, so a column added to a
  MERGE reaches production only if someone remembers to run the DDL by hand.

## 4. No networking restrictions

No VNet integration, no private endpoints, no `ipSecurityRestrictions`, no storage firewall. Every
Function App is reachable from the public internet and every storage account accepts traffic from
anywhere with the key.

Consumption (`Y1`) does not support VNet integration, so this is a consequence of the plan choice,
not an oversight. Restricting storage to selected networks would require Elastic Premium (`EP1`).

Inbound HTTP triggers are protected at the application layer instead -- see
`autoplan-integration-auth`.

## 5. No alerts that suit a timer-triggered app

The two baseline alerts are `Http5xx` and `AverageResponseTime`. Both are HTTP metrics. A
timer-triggered integration that never serves an HTTP request cannot trip either one.

What is missing is the alert that would actually have caught the incidents in this estate: a
failure-count alert, or a log-based alert on "no successful run in the last N hours". Neither
exists in any template.

Concretely: HubSpot's deals sync has been silently writing nothing to SQL (see
`autoplan-sql-model-alignment/references/known-defects.md`) and **no alert in the platform could
have detected it**, because the function returns 200 and reports success.

## 6. Alerts may notify nobody

`alertActionGroupResourceId` defaults to `''`, and `metricAlertActions` is then `[]`. Alerts are
created, enabled, and route to no one. Nothing in the template or the pipeline warns about this.

Check what a deployed environment actually has:

```bash
az monitor metrics alert list -g rg-echoes-prod --query "[].{name:name, actions:actions}" -o table
```

## 7. No `what-if` in the deploy path

The pipeline runs `az deployment group validate` before `create`, which checks the template is
syntactically valid and the parameters resolve. It does **not** show what will change.

`az deployment group what-if` would show the resource-level diff before a prod deploy. No pipeline
uses it, and `provision.ps1` does not either.

## Priority

If you fix one: **role assignments for the managed identity** (2). It unblocks Key Vault
references (1) and keyless storage access, and the identity is already declared in all six
templates -- the work is additive, not a migration.
