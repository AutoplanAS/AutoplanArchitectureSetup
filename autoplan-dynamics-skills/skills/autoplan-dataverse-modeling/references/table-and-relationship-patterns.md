# Dataverse table and relationship patterns

## Table design

- Record business capability and bounded context for every table to avoid cross-context leakage.
- Define required columns separately from optional integration payload fields.
- Prefer alternate keys for stable external identities used by integration upserts.

## Ownership

- Choose `user/team-owned` when row-level access and assignment workflows are required.
- Choose `organization-owned` for shared reference/configuration data without per-row ownership.
- Document why ownership type was chosen because changing it later is expensive.

## Relationships

- Define 1:N, N:1, and N:N relationships with explicit navigation intent.
- Decide cascade behavior per relationship (`Parental`, `Referential`, `Restrict`, etc.) before
  enabling delete-heavy operations.
- Keep lookup chains shallow for high-volume processes to reduce plugin/workflow complexity.

## Microsoft documentation trail

- Dataverse table definitions:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-metadata
- Define alternate keys:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/define-alternate-keys-entity
- Table relationships:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/create-update-entity-relationships-using-web-api
