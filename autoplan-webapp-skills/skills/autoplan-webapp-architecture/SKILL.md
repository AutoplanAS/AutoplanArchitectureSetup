---
name: autoplan-webapp-architecture
description: Design and plan lightweight web apps using the VehiclePortal split architecture (React frontend, Node API, Azure SQL, hybrid deployment).
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  source-repo: JoergenAmrudHagen/VehiclePortal
  lifecycle: design-plan
---

# Autoplan lightweight webapp architecture

Use this skill when defining architecture, solution boundaries, and delivery plans for lightweight web applications.

## Default target architecture

1. React SPA frontend (UI state and orchestration).
2. Node API backend with explicit route handlers.
3. Azure SQL as persistent store.
4. Hybrid hosting: frontend on Vercel, API on Azure App Service.

## Design rules

1. Keep frontend and API concerns separate. Frontend does not contain authorization logic as source of truth.
2. Keep API route handlers thin and move shared logic into internal modules (auth, DB, repository, errors, telemetry).
3. Make configuration explicit with environment variables and health endpoints.
4. Design for role-based access control from day one.
5. Prefer idempotent infrastructure and migration scripts.

## Planning workflow

1. Produce a boundary map (frontend modules, API modules, shared contracts).
2. Define RBAC matrix (admin/user or equivalent).
3. Define data model and persistence strategy (normalized columns vs JSON payload columns).
4. Define runbook endpoints (health, version, telemetry probes).
5. Define deploy topology (local, preview, production).

Read `references/architecture-principles.md` first, then `references/planning-checklist.md`.

