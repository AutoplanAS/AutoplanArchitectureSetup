# Planning checklist

Use this checklist before implementation starts.

## Scope and UX

- Define primary user roles and their allowed actions.
- Define which operations are frontend-only and which require backend persistence.
- Define localization expectations for user-facing error messages.

## API and data

- Define endpoint inventory and route ownership.
- Define canonical response schema per endpoint.
- Define SQL schema and where JSON payload storage is acceptable.
- Define migration and seed strategy for new environments.

## Operations

- Define required environment variables.
- Define health/version/telemetry verification endpoints.
- Define deployment topology and DNS/CORS boundaries.

## Delivery

- Define targeted automated tests for core auth and data flows.
- Define smoke test path for preview/prod validation.
- Define rollback criteria and fallback path.

