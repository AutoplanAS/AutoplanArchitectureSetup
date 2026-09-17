# Dynamics solution boundaries

## When this skill applies

Use this skill for work that primarily lives in Dynamics 365 or Dataverse:

- table and relationship design
- model-driven app/server-side automation decisions
- plugin, custom action, and workflow boundaries
- Dynamics Web API integrations
- release packaging and environment promotion decisions

Keep generic backend concerns in the backend bundle when the center of gravity is outside
Dynamics.

## Boundary decisions to make early

1. **System of record**
   - Identify which entities are authoritative in Dataverse and which are projections from another
     system.
   - Record ownership, retention, and synchronization direction per table.
2. **Extensibility model**
   - Prefer supported extension points such as plugins, custom actions, and the Web API.
   - Avoid assumptions that depend on direct SQL access or unsupported runtime hooks.
3. **Execution pipeline**
   - For every plugin step, document the message, primary table, filtering attributes, stage, and
     whether it must be synchronous or asynchronous.
   - Require deterministic behavior so retries or duplicate events do not corrupt state.
4. **Integration edge**
   - Make outbound calls through explicit integration boundaries and define auth, timeout, retry,
     and dead-letter handling.
   - Do not hide network dependencies inside broad plugin logic without failure policy.
5. **Operational ownership**
   - Decide where telemetry, alerting, and release validation live before delivery starts.

## Microsoft documentation trail

- Dynamics 365 developer overview:
  https://learn.microsoft.com/en-us/dynamics365/customerengagement/on-premises/developer/overview?view=op-9-1
- Dataverse developer overview:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/overview
- Plug-ins:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/plug-ins
