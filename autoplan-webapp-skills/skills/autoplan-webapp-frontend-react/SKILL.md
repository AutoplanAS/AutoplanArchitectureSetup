---
name: autoplan-webapp-frontend-react
description: Build and evolve React frontends for lightweight web apps with clear auth state, API integration boundaries, and maintainable component structure.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  source-repo: JoergenAmrudHagen/VehiclePortal
  lifecycle: develop-frontend
---

# Autoplan React frontend skill

Use this skill when building or refactoring the frontend for lightweight web apps.

## Core conventions

1. Keep auth bootstrap and session state in a dedicated context provider.
2. Keep API interaction in a centralized client module.
3. Keep page-level orchestration separate from reusable components.
4. Keep user-facing API failures translated into clear domain-friendly messages.
5. Keep feature logic decomposable to avoid monolithic root components.

## Delivery workflow

1. Define page/state model for the flow.
2. Implement component contracts and props first.
3. Wire API calls through the shared API client.
4. Handle loading/error states explicitly.
5. Keep admin-only UI paths aligned with backend-enforced role checks.

Read `references/app-composition.md` first, then `references/api-client-pattern.md`.

