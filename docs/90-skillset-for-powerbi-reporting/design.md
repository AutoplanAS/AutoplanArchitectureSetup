# Skillset for Power BI reporting

> **Status:** Proposed for review  
> **Issue:** #90  
> **Run token:** `autobot-spec-90-35215354779`

## 1. Problem and goal

AutoplanArchitectureSetup currently provides Autoplan skill bundles for backend/integration work and web application development, but it does not provide a focused skillset for Power BI reporting. Issue #90 requests a dedicated Power BI skillset with primary emphasis on DAX development and best practices.

Goal: define a first-class, installable Power BI reporting skill package that helps teams design semantic models, write maintainable DAX, review measures for correctness and performance, and produce reports that follow consistent delivery standards.

## 2. Scope

### In scope

- Introduce a new package: `autoplan-powerbi-skills/`.
- Define Power BI–focused skills using the existing `skills/<name>/SKILL.md` + `references/` structure used elsewhere in this repository.
- Make DAX best practices the core of the package, including modeling assumptions that directly affect DAX quality.
- Provide install/uninstall scripts aligned with the current package conventions.
- Update top-level documentation so Power BI is listed as an official Autoplan domain skillset and teams understand when to install it.

### Out of scope

- Creating customer-specific Power BI reports, datasets, or `.pbix` files in this repository.
- Building deployment automation for Power BI workspaces or gateways in this issue.
- Replacing the existing backend or webapp skillsets.

## 3. Functional design

### 3.1 Package structure

Create a new folder with the same package shape used by the existing Autoplan skill bundles:

- `autoplan-powerbi-skills/README.md`
- `autoplan-powerbi-skills/scripts/Install-Skills.ps1`
- `autoplan-powerbi-skills/scripts/Uninstall-Skills.ps1`
- `autoplan-powerbi-skills/skills/<powerbi-skill>/SKILL.md`
- `autoplan-powerbi-skills/skills/<powerbi-skill>/references/*.md`

The installer should support the same target and mode conventions already used by the current Autoplan packages so Power BI skills can be adopted without introducing a different operating model.

### 3.2 Initial Power BI skill set

Provide an initial set of skills that cover the main reporting workflow, while keeping DAX as the primary focus:

1. **Power BI model architecture**
   - Define when to use star schema modeling, conformed dimensions, fact grain, and surrogate keys.
   - Explain how relationship direction, cardinality, and ambiguous paths affect DAX behavior.
   - Guide authors toward model shapes that support reliable filter propagation and performant measures.

2. **DAX development and review**
   - Emphasize measures over implicit aggregations and discourage fragile calculated-column usage where measures are more appropriate.
   - Cover row context, filter context, context transition, `CALCULATE`, iterators, variables, and branching patterns.
   - Include best-practice guidance for naming, formatting, reusable base measures, time intelligence, safe division, blank handling, and avoiding logic duplication.
   - Include a review checklist for correctness, readability, and performance risks.

3. **Report design and consumer usability**
   - Cover report-page structure, slicer behavior, drill paths, visual interactions, KPI clarity, and accessibility basics.
   - Ensure the skillset connects report layout decisions back to semantic-model and DAX choices.

4. **Testing and performance diagnostics**
   - Define how authors validate measures with representative scenarios and edge cases.
   - Cover techniques such as checking totals/subtotals, validating filter combinations, and using Power BI performance tooling to detect expensive DAX patterns.

### 3.3 DAX best-practice expectations

The DAX-oriented skill content should standardize the following expectations:

- Prefer explicit measures with clear naming over ad hoc visual calculations.
- Use variables to make complex measures readable and reduce repeated expressions.
- Keep business logic centralized in reusable base measures where possible.
- Treat filter context changes as explicit design decisions and document any non-obvious use of `ALL`, `REMOVEFILTERS`, `KEEPFILTERS`, or context transition.
- Favor semantic-model design that reduces the need for workaround DAX.
- Include performance awareness from the start, especially for iterator-heavy logic and large fact tables.

### 3.4 Documentation integration

Update the root documentation so Power BI becomes a standard option alongside backend and webapp skillsets:

- Add Power BI to the layered skillset overview.
- Add install instructions for the new package.
- Extend the “Which skillsets to use” guidance with Power BI-only reporting scenarios and mixed projects where backend + Power BI skills are both relevant.

## 4. Acceptance criteria

- **AC-1:** Repository contains `autoplan-powerbi-skills/` with README, install/uninstall scripts, and skill folders following existing package conventions.
- **AC-2:** The package includes at least one substantive DAX-focused skill with actionable authoring and review guidance.
- **AC-3:** The skillset documents model-design guidance that is directly relevant to DAX correctness and maintainability.
- **AC-4:** Root documentation clearly lists Power BI as an available Autoplan domain skillset and explains when to install it.
- **AC-5:** The initial skillset includes verification guidance for both logical correctness and DAX/report performance.

## 5. Risks and mitigations

- **Risk:** The package becomes too broad and drifts into generic BI governance.  
  **Mitigation:** keep the first version centered on semantic-model design, DAX quality, and report-delivery practices that directly support day-to-day reporting work.

- **Risk:** DAX guidance becomes a list of isolated formulas instead of transferable engineering practice.  
  **Mitigation:** structure the skills around reusable decision rules, review checklists, and patterns tied to context handling and model design.

- **Risk:** Power BI overlaps awkwardly with backend skills in mixed data projects.  
  **Mitigation:** define the boundary clearly: backend skills own data acquisition/integration and operational delivery, while Power BI skills own reporting model, DAX, and report-consumer design concerns.

## 6. Verification approach

- Validate the package layout and documentation updates against the acceptance criteria.
- Review the skill content to confirm DAX best-practice guidance is concrete, opinionated, and actionable.
- Verify installer behavior matches the conventions already used by the other Autoplan skill packages.
- Review the package boundary against existing backend/webapp docs to ensure Power BI adoption guidance is clear and non-conflicting.
