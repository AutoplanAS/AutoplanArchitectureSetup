# Dynamics implementation checklist

## Dataverse model

- Name the tables, primary keys, ownership type, and required alternate keys.
- Document relationship cardinality and cascading behavior before automation depends on it.
- Identify columns that trigger automation and columns that must be ignored to avoid recursion.

## Server-side logic

- For each plugin/action/workflow, record:
  - message and primary table
  - pipeline stage and execution mode
  - pre/post image requirements
  - idempotency expectations
  - user-facing error strategy
- Keep plugin handlers focused on one business responsibility.

## Integration usage

- Prefer the Dynamics Web API for external callers.
- Define authentication model, throttling expectations, and retry policy for every integration.
- Separate transport concerns from business rules so failures are observable and recoverable.

## Validation and release

- Define unit tests for mapping and business-rule logic.
- Define integration or sandbox validation for plugin registration, security roles, and event flow.
- Verify managed/unmanaged solution packaging, required environment variables, and deployment
  sequencing before release approval.

## Microsoft documentation trail

- Dynamics 365 developer overview:
  https://learn.microsoft.com/en-us/dynamics365/customerengagement/on-premises/developer/overview?view=op-9-1
- Dataverse developer overview:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/overview
- Plug-ins:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/plug-ins
