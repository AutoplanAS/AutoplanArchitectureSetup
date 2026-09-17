# Dataverse lifecycle and performance

## Data lifecycle decisions

- Define status/state transitions and who is allowed to execute each transition.
- Define retention boundaries (operational data vs archived history) and archival trigger criteria.
- Ensure automation handling deactivation/reactivation is explicit to avoid silent regressions.

## Performance decisions

- Design read paths around selective filters and supported query expressions.
- Limit automation triggers to required columns using filtering attributes for plugin steps.
- Avoid synchronous plugin logic that performs long-running network I/O.
- Validate volume assumptions with representative test data before release.

## Delivery validation

- Verify largest expected entity sets for query latency and timeout behavior.
- Verify plugin/workflow side effects under bulk update/import scenarios.
- Verify indexes/keys used by integration upsert flows match production lookup patterns.

## Microsoft documentation trail

- Optimize performance in Dataverse:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optimize-performance-create-update
- Query data using Web API:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/query/overview
- Plug-in registration and filtering attributes:
  https://learn.microsoft.com/en-us/power-apps/developer/data-platform/register-plug-in
