# Autobot pipeline design (superseded)

> **Status:** Superseded by the provider-agnostic workflow contract

This document is retained for historical context only.

The current Autobot workflow contract is documented in:

- `docs/autobot-provider-agnostic-workflow-contract/design.md`

Use that document as the single source of truth for:

- lifecycle labels and stage transitions;
- provider-agnostic behavior across Codex and GitHub Copilot;
- `autobot-ready-to-implement` rollover to a new main feature issue;
- implementation trigger `autobot-implementing` and terminal review state `autobot-in-review`;
- human-gated rework behavior (no automatic phase skipping or auto-restart from PR feedback);
- spec artifact mirror behavior (`design.md` and `design.html`) with branch-scoped `latest.json`;
- SAS-only Azure Blob publishing requirements and security constraints;
- acceptance criteria AC-1 through AC-27.
