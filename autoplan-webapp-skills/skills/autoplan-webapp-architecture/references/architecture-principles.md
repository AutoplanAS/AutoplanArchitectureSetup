# Architecture principles (VehiclePortal baseline)

## Source patterns

- Frontend orchestration: `src/App.js`, `src/AuthContext.js`
- API boundary: `api/*`, `server.js`
- Shared backend building blocks: `api/_auth.js`, `api/_db.js`, `api/_errors.js`, `api/_telemetry.js`
- Infrastructure baseline: `infra/main.bicep`

## Baseline decisions

1. **Split runtime model**  
   Keep frontend and backend independently deployable. Frontend consumes API through a configurable base URL (`src/apiClient.js`).

2. **API handler contract**  
   Each handler validates method, validates auth, validates input, executes repository/service logic, and returns stable JSON response shape.

3. **RBAC enforced in API**  
   Role and company scoping are checked server-side in every protected endpoint.

4. **Observability built-in**  
   App Insights hooks and explicit health/version endpoints are part of the first release, not an afterthought.

5. **Config-driven environments**  
   Runtime behavior is defined via env vars for SQL, JWT, CORS, telemetry, and frontend API base URL.

