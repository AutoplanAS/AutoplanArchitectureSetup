# Smoke and regression checks

## Source patterns

- API smoke: `smoke_test.js`, `test_smoke.js`, `scripts/smoke-focalx.js`, `scripts/smoke-focalx-prod.js`
- Runtime version probe: `api/health/version.js`
- Telemetry probe: `api/health/telemetry.js`

## Smoke checklist

1. Verify runtime health endpoint is reachable.
2. Verify auth login and auth/me flow.
3. Verify one read and one write path for core business data.
4. Verify deployment identity with `GET /api/health/version`.
5. Verify telemetry configuration with `GET /api/health/telemetry`.

## Regression discipline

- Keep one canonical smoke path per environment.
- Keep smoke scripts aligned with current auth mechanism (Bearer token).
- Treat smoke failures as release blockers until explained.

