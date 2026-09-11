---
name: autoplan-webapp-auth-data
description: Implement JWT auth, RBAC, and Azure SQL persistence for lightweight web apps using stable, environment-driven configuration and idempotent migrations.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  source-repo: JoergenAmrudHagen/VehiclePortal
  lifecycle: develop-auth-data
---

# Autoplan auth and data skill

Use this skill when implementing authentication/authorization and persistence.

## Auth baseline

1. Use JWT with explicit expiration and signed claims.
2. Include role and tenant/company claims needed for RBAC enforcement.
3. Validate bearer tokens server-side in protected routes.
4. Keep password hashing explicit and strong (`bcrypt` with consistent cost factor).

## Data baseline

1. Use central SQL configuration resolver with connection-string-first behavior.
2. Keep query parameterization strict.
3. Keep migration scripts idempotent.
4. Support optional seed data for first-run environments.
5. Use JSON payload columns only when they preserve UI contract intentionally.

Read `references/jwt-rbac.md` first, then `references/sql-and-migrations.md`.

