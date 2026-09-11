# Error mapping and telemetry

## Source patterns

- SQL error mapper: `api/_errors.js`
- Telemetry bootstrap and tracking: `api/_telemetry.js`
- Shared DB layer exception tracking: `api/_db.js`
- Express error middleware: `server.js`

## Rules

1. Map SQL error classes (constraint, FK, validation) to deterministic status codes.
2. Log/track with stage context (`db-query`, `db-connect`, route/method).
3. Keep telemetry non-blocking, but never fake success when core logic fails.
4. Return safe error messages to client while preserving actionable internal context.

## Operational endpoints

- `GET /api/health/telemetry`
- `GET /api/health/version`

Use them to verify runtime configuration and deployed build identity.

