# Vercel + App Service configuration pattern

## Source patterns

- Vercel build/deploy config: `vercel.json`
- API host process: `server.js`
- Infrastructure baseline: `infra/main.bicep`, `infra/main.parameters.json`
- Deployment context: `.azure/deployment-plan.md`

## Required environment contract

### Frontend

- `REACT_APP_API_BASE_URL`

### API

- `SQLSERVER_CONNECTION_STRING` (or discrete `AZURE_SQL_*`)
- `JWT_SECRET`
- `CORS_ALLOWED_ORIGINS`
- `APPLICATIONINSIGHTS_CONNECTION_STRING` or `APPINSIGHTS_INSTRUMENTATIONKEY`

## Important consistency checks

1. Frontend points to intended API host (not stale endpoint).
2. API CORS includes exact frontend origin.
3. API runtime can establish SQL connection.
4. App Insights configuration exists in the actual API host runtime.

