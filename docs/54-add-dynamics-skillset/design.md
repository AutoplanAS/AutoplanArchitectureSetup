# Add Dynamics 365 skillset

> **Status:** Proposed for review  
> **Issue:** #54  
> **Run token:** `autobot-spec-54-35128161820`

## 1. Problem and goal

AutoplanArchitectureSetup currently packages two Autoplan domain skillsets: backend integration and lightweight webapp development. We need to add a third domain skillset focused on Microsoft Dynamics 365 development so teams can use the same skill-driven delivery model when building Dataverse, plugin, workflow, and Dynamics API integrations.

Goal: define a first-class, installable Dynamics skill package with the same structure, install flow, and governance model used by existing Autoplan skill packages.

## 2. Scope

### In scope

- Introduce a new package: `autoplan-dynamics-skills/`.
- Add Dynamics-focused skills using the existing portable `skills/<name>/SKILL.md` + `references/` pattern.
- Provide install/uninstall scripts consistent with existing package behavior (target support and auto symlink/copy mode).
- Update top-level documentation so Dynamics appears as an official Autoplan domain skillset and recommended setup option.

### Out of scope

- Runtime code for specific Dynamics customer projects.
- Changes to Autobot workflow logic.
- Replacing existing backend or webapp skillsets.

## 3. Functional design

### 3.1 Package structure

Create a new folder:

- `autoplan-dynamics-skills/README.md`
- `autoplan-dynamics-skills/scripts/Install-Skills.ps1`
- `autoplan-dynamics-skills/scripts/Uninstall-Skills.ps1`
- `autoplan-dynamics-skills/skills/<dynamics-skill>/SKILL.md`
- `autoplan-dynamics-skills/skills/<dynamics-skill>/references/*.md`

The package follows the same conventions as `autoplan-backend-skills` and `autoplan-webapp-skills` to keep onboarding and maintenance uniform.

### 3.2 Initial Dynamics skill set

Define an initial set of skills that cover common Dynamics 365 engineering work:

1. **Solution architecture and boundaries** (entities, bounded contexts, integration edges).
2. **Dataverse modeling and data lifecycle** (tables, relationships, ownership, data quality, performance).
3. **Server-side logic and extensibility** (plugins, custom workflow/actions, execution pipeline, telemetry, failure handling).
4. **Integration and API usage** (Web API, auth model, external system integration patterns).
5. **Testing and release practices** (unit/integration test strategy, ALM, deployment checks).

Reference content should align with Microsoft Dynamics documentation identified in issue #54.

### 3.3 Documentation integration

Update root docs so Dynamics is discoverable and treated as a standard option:

- Add Dynamics skillset to the layered model.
- Add install step(s) alongside backend/webapp install steps.
- Extend “Which skillsets to use” guidance with Dynamics scenarios (Dynamics-only and mixed integration stacks).

## 4. Acceptance criteria

- **AC-1:** Repository contains `autoplan-dynamics-skills/` with README, install/uninstall scripts, and skill folders following existing package conventions.
- **AC-2:** At least one substantive Dynamics skill exists with actionable `SKILL.md` instructions and deeper `references/` content.
- **AC-3:** Root documentation clearly lists Dynamics as an available Autoplan domain skillset and shows how to install it.
- **AC-4:** Dynamics guidance is traceable to Microsoft Dynamics 365 developer documentation.

## 5. Risks and mitigations

- **Risk:** Skill overlap with backend package creates unclear ownership.  
  **Mitigation:** define Dynamics scope boundaries explicitly (Dataverse/app platform concerns vs generic backend integration concerns).

- **Risk:** Guidance becomes too vendor-doc heavy and not actionable in delivery tasks.  
  **Mitigation:** keep `SKILL.md` concise/task-oriented and move deep references into `references/`.

- **Risk:** Installer behavior diverges from existing skill packages.  
  **Mitigation:** reuse the same script interface and defaults used by current Autoplan packages.

## 6. Verification approach

- Validate package layout and file presence against acceptance criteria.
- Run PowerShell install/uninstall scripts in dry-run or sandbox verification to confirm expected target paths and mode behavior.
- Review top-level docs for complete Dynamics additions and consistency with existing sections.
