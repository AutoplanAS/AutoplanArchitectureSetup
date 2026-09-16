# Copilot autonomous spec test 20260916-145455

> **Status:** Proposed for review
> Feature: #62.

## 1. Requirements: what and why

Issue #62 validates the Copilot spec handoff path for this repository. After the feature issue is labelled `autobot-ready-for-spec`, the automation should produce the required design document at `docs/<issue-slug>/design.md` without requiring a human to create the file or manually complete the spec artifact.

The outcome for this handoff PR is intentionally narrow: create the required design document for issue #62, keep the PR tied to `#62`, preserve the run token in PR metadata, and mark `.autobot/output/spec.json` as completed so the completion workflow can accept the handoff.

## 2. User experience

A maintainer labels issue #62 for the spec phase and receives a handoff PR. Opening the PR shows a populated design document at `docs/62-copilot-autonomous-spec-test-20260916-145455/design.md` instead of a placeholder or missing artifact.

The reviewer can confirm that the design exists, that the PR still references `#62`, and that the recorded phase output reports completion. No source code, workflow logic, or unrelated documentation changes are needed for this test.

## 3. Technical design and choices

Create the required Markdown design file directly in the deterministic issue-specific docs path derived from the issue number and slug. Use the repository's existing design-document style with concise sections covering requirements, user experience, implementation intent, and acceptance evidence.

Update `.autobot/output/spec.json` from `in_progress` to `completed`, clear the blocked reason, and provide the completion metadata expected by the spec workflow:

- `issue_comment` points reviewers to the generated design document.
- `pr_title` remains `Autobot spec handoff for issue #62`.
- `pr_body` preserves the existing handoff description, `#62` reference, and run token `autobot-spec-62-35098641901`.

This keeps the completion artifact aligned with the already-open PR while avoiding any broader repository changes.

## 4. Acceptance and proof

This handoff is complete when all of the following are true:

1. `docs/62-copilot-autonomous-spec-test-20260916-145455/design.md` exists in this branch and contains real design content.
2. `.autobot/output/spec.json` contains `status: "completed"`.
3. The PR metadata recorded in `.autobot/output/spec.json` still references `#62` and includes the run token `autobot-spec-62-35098641901`.
4. No unrelated files are changed.

## 5. Open questions

No open design questions remain for this spec handoff itself. The test is successful once the required artifact path and completion metadata are present in the branch for review.
