# SQL configuration and migrations

## Source patterns

- SQL connection handling: `api/_db.js`
- Schema and seed migration: `scripts/migrate.js`
- Repository queries: `api/vehicles/_repository.js`

## Configuration precedence

1. Prefer `SQLSERVER_CONNECTION_STRING`.
2. Fall back to discrete variables (`AZURE_SQL_*` / `SQL_*`) only when needed.
3. Fail loudly when required SQL config is missing.

## Migration rules

1. Use idempotent `IF OBJECT_ID ... IS NULL` table creation.
2. Add required indexes idempotently.
3. Keep seed logic deterministic and safe for repeat runs.
4. Keep schema, repository expectations, and API response model aligned.

