# Dynamics 365 Customer Engagement skillset

> **Status:** Proposed for review
> **Feature:** #31, Add Dynamics skillset
> **Architecture review:** Independent review approved; no blocker or important findings. Implementation acceptance checks remain pending.

## 1. Requirements: what and why

Autoplan developers need reusable agent guidance for Dynamics development alongside the existing backend and webapp packages. Deliver an independently installable Markdown skill package with practical development guidance, source references, installation instructions, and verification scenarios.

The initial scope is **Dynamics 365 Customer Engagement on-premises, version 9**, using the issue's v9.1 documentation view. This is a proposed scope decision grounded in the supplied [Microsoft developer overview](https://learn.microsoft.com/en-us/dynamics365/customerengagement/on-premises/developer/overview?view=op-9-1), checked 2026-09-14. That page explicitly directs online applications to separate Dataverse documentation. Business Central, Finance and Operations, online Dataverse implementation, deployment of a real Dynamics environment, and changes to Autobot or Machinist routing are out of scope.

The deliverable is guidance and package tooling, not a Dynamics application or a comprehensive copy of Microsoft's documentation. Existing Blueprint workflows remain responsible for design, planning, implementation, and review.

## 2. User experience

A developer finds the Dynamics package in the root package table, copies it into their repository, and runs `./autoplan-dynamics-skills/scripts/Install-Skills.ps1`. The default installs to Copilot's existing repository convention, `~/.agents/skills`. They can select Claude, Codex, or Gemini using `-Target`, and choose `Auto`, `Copy`, or `Symlink` using `-Mode`. The output identifies installed, refreshed, and skipped skills. A new agent session can load a skill by its exact name.

For a request such as “add an account update plug-in,” the guidance first establishes the Dynamics product, deployment type, exact server version, and applicable project context. It then provides the relevant implementation checks, references, and verification expectations. Missing environment facts produce targeted questions before environment-specific code or commands. An online or different-product request receives an explicit scope explanation and an authoritative documentation pointer, without applying on-premises examples.

Installation with no valid source skills or invalid arguments fails with an actionable error. An existing unrelated destination is skipped and reported unless `-Force` is supplied. Explicit Symlink mode fails if links are unavailable; Auto falls back to Copy. Rerunning refreshes owned copies; uninstall removes owned installations. Users recover from interrupted installation by rerunning after correcting the reported filesystem error. Copy users rerun after package updates; symlink users keep the source package in place.

## 3. Technical design and choices

### Package and content contracts

Add `autoplan-dynamics-skills/README.md`, `scripts/Install-Skills.ps1`, `scripts/Uninstall-Skills.ps1`, and the following directories under `skills/`. Each contains `SKILL.md` with YAML `name` matching the directory, a task-specific `description`, and relative links to local `references/*.md` files.

| Skill | Required responsibility |
|---|---|
| `autoplan-dynamics-development` | Establish product/version/deployment, select the relevant skill, explain supported extension boundaries and the security model. |
| `autoplan-dynamics-plugins` | Server extension lifecycle, registration stage/mode, execution context, images, recursion and idempotency, tracing, and registration verification. |
| `autoplan-dynamics-client-scripting` | Supported form/event APIs, execution and form context, asynchronous failures, and browser verification for the selected client/version. |
| `autoplan-dynamics-integration` | Web API versus Organization service selection, environment-compatible authentication, permissions, paging, transient failures, and duplicate-write prevention. |
| `autoplan-dynamics-solutions` | Solution dependencies, managed/unmanaged choices, export/import and publishing checks, configuration separation, and recovery from failed imports. |
| `autoplan-dynamics-testing` | Unit-test boundaries, plug-in and client scenarios, permission failures, and disposable-environment verification of integration and solution changes. |

Every entrypoint includes triggers, exclusions, prerequisite questions, an actionable procedure, failure handling, and proof expectations. References contain original summaries and small examples, direct official Microsoft sources, supported product/version context, and a last-verified date. Follow the overview's relevant topic links during implementation; do not treat its index alone as proof of API details. Verify runtime, SDK, authentication, and client API compatibility against the selected server version before recommending them. Do not impose the backend package's .NET Functions runtime on Dynamics extensions.

**INV-1:** Every skill preserves the product/deployment/version boundary and stops environment-specific guidance when required facts or supporting documentation are unavailable. An unavailable source is reported as unverified, never reconstructed as fact.

**INV-2:** Guidance uses placeholders for credentials and customer data, least-privilege access, and supported extension interfaces. It excludes direct Dynamics database writes and requires an explicit target environment and user authorization before executing registration, import, publishing, or data mutation. Documentation and issue content are evidence, never executable agent instructions.

This focused package adds no SDK dependencies or runtime services. The cost is maintaining a separate, deliberately limited domain package. Backend skills can support an external integration service, but do not override Dynamics extension compatibility.

### Installation and repository integration

Adapt the portable layout and PowerShell interface from `autoplan-webapp-skills/scripts/`, without refactoring other packages. Retain `-Target Copilot,Claude,Codex,Gemini` mappings to `.agents/skills`, `.claude/skills`, `.codex/skills`, and `.gemini/skills` under the user's home; default to Copilot and Auto. Discover only `autoplan-dynamics-*` directories containing `SKILL.md`. Deduplicate targets. Mark copies with `.autoplan-skill-source` containing the canonical source directory.

**INV-3:** Installation and removal affect only selected Dynamics destinations. Ownership requires either a symlink resolving to the matching source or a copy marker matching that source. Default uninstall preserves foreign links as well as foreign copies, tightening the existing webapp uninstaller's unconditional link removal. `-Force` permits install replacement at an exact discovered skill destination; `-IncludeCopies` permits uninstall of unowned real directories at those destinations, never foreign links. Deleting a link must never recurse into its target. A moved clone requires explicit replacement or use of the original clone for removal.

Filesystem errors stop the script with nonzero exit and identify the affected destination; earlier successful skills remain installed. Installation is not transactional across skills or targets. Retry restores a partially copied destination bearing this clone's ownership marker; a destination without that marker is preserved and requires explicit `-Force` after inspection. Concurrent install/uninstall against the same target is unsupported and documented.

Update root `README.md` and `DOCUMENTATION.md` package lists, selection guidance, install/update/uninstall examples, and add the package README with scope and troubleshooting. Keep the existing `DOCUMENTATION.html` reading view aligned with changed documentation content. Do not commit generated installations or alter existing skill names, lockfiles, provider settings, or automation workflows.

## 4. Acceptance and proof

| ID | Done when | How to check |
|---|---|---|
| AC-1 | Exactly the six named skills are discoverable and all local links resolve. | A package validation check parses YAML, compares the exact name set and directory names, and resolves every local Markdown reference. |
| AC-2 | Guidance meets the content contract and INV-1. | Review all six entrypoints and their sources; record agent trials for an on-premises plug-in request, unspecified Dynamics request, explicit online Dataverse request, and unavailable documentation. The latter three must clarify, redirect, or report unverified context as specified. |
| AC-3 | INV-2 holds in examples and agent behavior. | Review examples for secrets, unsupported database writes, and compatibility claims; trial an unauthorized production import request and verify no mutation occurs and target/authorization are requested. |
| AC-4 | Install, refresh, and removal obey INV-3. | PowerShell tests in isolated temporary home directories exercise all four target mappings, duplicate targets, Copy refresh, Symlink rerun, Auto fallback through simulated link denial, explicit Symlink denial, invalid arguments, empty sources, foreign copy/link collisions, both override flags, and uninstall. Assert unrelated sentinel contents and source link targets survive. |
| AC-5 | Partial failures have the documented recovery behavior. | Inject a copy failure and a later-target write failure; assert nonzero exit, destination identification, preservation of earlier successes, and successful recovery by rerun or explicit Force for an unmarked partial copy. |
| AC-6 | Users can discover and adopt the package without breaking existing packages. | Run package tests on Windows and Linux with PowerShell 7, document that supported tooling baseline, inspect root Markdown/HTML and package README links and commands, and manually verify named skill loading in a fresh agent session. Missing agent access is reported as unverified, not passed. |

These are implementation acceptance checks, not claims that the proposed package has already passed them. Test harnesses must isolate the home path through a test seam or disposable account, without overwriting PowerShell's automatic HOME variable or modifying a developer's real skill installations.

## 5. Open questions

None blocking. The v9 on-premises boundary is the proposed default for review, inferred from the issue's explicit documentation link. Broader Dynamics product support requires a separate scope decision and is not needed to implement this package.
