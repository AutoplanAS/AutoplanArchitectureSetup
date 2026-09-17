---
name: autoplan-dynamics-architecture
description: Design and plan Dynamics 365 and Dataverse solutions with clear table boundaries, plugin execution rules, and integration constraints.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  lifecycle: design-plan
---

# Autoplan Dynamics 365 architecture

Use this skill when defining Dynamics 365 solution boundaries, Dataverse data design, plugin or
workflow behavior, and integration responsibilities.

## Default design checklist

1. Define which business capability stays inside Dynamics and which moves to external services.
2. Model Dataverse tables, ownership, relationships, and lifecycle rules before writing plugins.
3. Keep server-side automation explicit: plugin step, execution stage, triggering columns, and
   failure/telemetry behavior.
4. Prefer Web API and supported extensibility points over direct database assumptions.
5. Plan testing, ALM, and release checks alongside the solution design.

## Delivery workflow

1. Capture the solution boundary map and integration edges.
2. List Dataverse tables, keys, ownership model, and required relationships.
3. Specify each plugin/action/workflow trigger with stage, sync/async behavior, and idempotency.
4. Define external API usage, authentication, and retry/error handling expectations.
5. Define validation, test coverage, and deployment gates before implementation starts.

Read `references/solution-boundaries.md` first, then `references/implementation-checklist.md`.

If the request is primarily table schema, ownership, lifecycle, or performance design, use
`autoplan-dataverse-modeling` together with this skill.
