# Design: Spec auto-assignee verification issue 60

## Purpose
Verify that Copilot spec handoff PR auto-assignment and completion gating work as expected.

## Validation steps
- Handoff PR should be assigned to configured Copilot assignee.
- Completion should stay pending before design exists.
- Completion should transition to review after design file is added.