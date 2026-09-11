---
name: autoplan-webapp-testing-quality
description: Add focused API and smoke validation for lightweight web apps, with tests that enforce auth, RBAC, payload shape, and endpoint behavior.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  source-repo: JoergenAmrudHagen/VehiclePortal
  lifecycle: test-validate
---

# Autoplan testing and quality skill

Use this skill when adding or reviewing automated validation.

## Test strategy

1. Prioritize API contract tests for auth and data endpoints.
2. Use unit-style handler tests with HTTP/request mocks for speed and determinism.
3. Keep smoke tests for environment-level verification (routing, auth, health).
4. Ensure tests assert behavior that matters, not just status code happy paths.

## Required coverage for new API capabilities

1. Method rejection (405).
2. Auth required / token invalid paths.
3. Role or tenant scoping logic.
4. Persistence side effects and response normalization.
5. Error mapping behavior.

Read `references/api-tests.md` first, then `references/smoke-and-regression.md`.

