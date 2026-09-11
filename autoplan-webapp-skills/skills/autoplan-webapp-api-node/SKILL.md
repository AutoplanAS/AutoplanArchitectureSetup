---
name: autoplan-webapp-api-node
description: Implement Node API handlers for lightweight web apps with strong method guards, explicit auth checks, mapped database errors, and telemetry.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  source-repo: JoergenAmrudHagen/VehiclePortal
  lifecycle: develop-api
---

# Autoplan Node API skill

Use this skill when implementing or refactoring API endpoints.

## Handler standard

1. Reject unsupported HTTP methods with a clear 405 response.
2. Enforce authentication and role checks before data operations.
3. Validate request payload shape before persistence.
4. Keep SQL access in repository/helper modules.
5. Map SQL/runtime failures to stable API error responses.
6. Track exceptions and traces with contextual metadata.

## Hosting model

Support both:

1. Function-style handlers in `api/*`.
2. Standalone Express host for App Service in `server.js`.

Route behavior must be consistent across both hosts.

Read `references/handler-pattern.md` first, then `references/error-and-telemetry.md`.

