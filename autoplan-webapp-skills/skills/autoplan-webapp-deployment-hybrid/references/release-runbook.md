# Release runbook

## Pre-release

1. Ensure migrations are applied for target environment.
2. Confirm required API and frontend env vars are present.
3. Confirm infrastructure parameters have non-empty secrets.

## Release

1. Deploy API package to Azure App Service.
2. Deploy frontend build to Vercel.
3. Set or confirm `REACT_APP_API_BASE_URL` in Vercel project settings.

## Post-release validation

1. `GET /api/health/version` returns expected runtime host and commit metadata.
2. `GET /api/health/telemetry` shows telemetry configured.
3. Login and `GET /api/auth/me` succeed.
4. Vehicle list and create/update paths succeed for intended roles.

## Rollback

1. Revert API deployment to previous known-good build.
2. Revert frontend deployment target if API URL contract changed.
3. Re-run post-release validation against rollback build.

