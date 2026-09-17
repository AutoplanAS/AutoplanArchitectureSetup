---
name: autoplan-dataverse-modeling
description: Design Dataverse table models with explicit ownership, relationships, lifecycle, and performance constraints for Dynamics 365 delivery work.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  lifecycle: design-plan
---

# Autoplan Dataverse modeling

Use this skill when the task is primarily Dataverse schema and data behavior: table design,
relationships, ownership, lifecycle, and query/write performance planning.

## Delivery checklist

1. Define each table purpose, primary name column, alternate keys, and authoritative source.
2. Pick ownership (`user/team` vs `organization`) from the access model before automation is
   implemented.
3. Specify relationship cardinality and cascading behavior for delete/assign/share operations.
4. Define lifecycle rules: active/inactive states, retention/archival expectations, and audit
   requirements.
5. Validate performance expectations: selective queries, indexed lookup patterns, and automation
   trigger columns.

## Boundary rule

- Put Dynamics platform concerns (Dataverse schema, plugin triggers, security model) in this
  bundle.
- Put generic integration orchestration that is platform-agnostic in backend skills.

Read `references/table-and-relationship-patterns.md` first, then
`references/lifecycle-and-performance.md`.
