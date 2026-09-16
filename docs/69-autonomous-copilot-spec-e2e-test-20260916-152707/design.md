# Autonomous Copilot spec E2E test

> **Status:** Proposed for review  
> **Issue:** #69  
> **Run token:** `autobot-spec-69-35102007359`

## 1. Problem and goal

We need an end-to-end validation that the Autobot spec phase can complete autonomously through GitHub Copilot handoff. The flow must prove that:

- Copilot instruction comments can be posted with the configured trigger token/handle,
- Copilot can generate the required design artifact in the handoff PR branch,
- in-run completion polling can detect artifact completion and advance the phase output,
- no manual PR comments or manual artifact edits are required.

This test is specifically for the spec phase contract and not for plan/implement execution.

## 2. Scope

### In scope

- Label-driven spec workflow entry for issue #69.
- Copilot handoff PR generation.
- Required artifact path creation at:
  - `docs/69-autonomous-copilot-spec-e2e-test-20260916-152707/design.md`
- Finalization of `.autobot/output/spec.json` with completed status.
- Preservation of issue linkage and run token traceability in PR metadata/comments.

### Out of scope

- Plan and implementation phase execution.
- Changes to provider routing beyond existing configuration.
- New runner infrastructure or permission model changes.

## 3. Functional design

### Trigger and handoff

1. Spec workflow starts from the expected Autobot label lifecycle for issue #69.
2. Workflow creates/updates a spec handoff PR branch and posts Copilot instructions.
3. Instruction includes the required design file path and run token for traceability.

### Copilot completion behavior

1. Copilot generates this design document in the required path.
2. Workflow completion polling checks for:
   - existence of `docs/69-autonomous-copilot-spec-e2e-test-20260916-152707/design.md`,
   - non-placeholder design content,
   - updated `.autobot/output/spec.json` with completed phase output.
3. On success, spec phase is marked completed and published through existing workflow contracts.

### Artifact contract for this run

The final `.autobot/output/spec.json` must include:

- `status`: `completed`
- `blocked_reason`: empty
- completion-ready `issue_comment`
- PR metadata fields (`pr_title`, `pr_body`) retaining reference to issue #69 and run token `autobot-spec-69-35102007359`

## 4. Acceptance criteria

- **AC-1:** Required design file exists at the exact path and contains substantive design content.
- **AC-2:** `.autobot/output/spec.json` is valid JSON and sets `status` to `completed`.
- **AC-3:** Issue #69 remains referenced in PR metadata.
- **AC-4:** Run token `autobot-spec-69-35102007359` is retained in PR body or PR comments.
- **AC-5:** Completion is achieved without manual PR comment/edit intervention outside the automated/copilot handoff flow.

## 5. Risks and mitigations

- **Risk:** Polling timeout before Copilot finishes.  
  **Mitigation:** keep timeout aligned with configured Copilot handoff SLA and surface blocked reason when incomplete.

- **Risk:** Artifact path mismatch due to slug drift.  
  **Mitigation:** enforce exact required path from handoff payload and validate before marking completion.

- **Risk:** Partial completion (design exists, JSON not finalized).  
  **Mitigation:** require both artifact checks and JSON status checks before success.

## 6. Verification approach

- Confirm the design file path and content in the PR branch.
- Validate `.autobot/output/spec.json` schema fields and completed status.
- Verify run token visibility in PR body/comments.
- Confirm issue #69 linkage remains present.
