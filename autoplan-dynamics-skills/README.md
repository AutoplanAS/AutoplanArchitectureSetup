# Autoplan Dynamics 365 skills

This package contains an installable Dynamics 365 skillset for planning and delivering Dataverse,
plugin, workflow, and Dynamics API work using the same portable skill format as the other
Autoplan bundles.

## Included skills

- `autoplan-dynamics-architecture`

## Skill format

Each skill follows the portable agent-skill layout:

- `skills/<skill-name>/SKILL.md`
- `skills/<skill-name>/references/*.md`

`SKILL.md` is the task-facing instruction entrypoint. `references/` contains deeper delivery
guidance and source links back to Microsoft Dynamics documentation.

## Install

Run from repository root:

```powershell
.\autoplan-dynamics-skills\scripts\Install-Skills.ps1
```

Default target:

```text
~\.agents\skills
```

Other agents:

```powershell
.\autoplan-dynamics-skills\scripts\Install-Skills.ps1 -Target Claude
.\autoplan-dynamics-skills\scripts\Install-Skills.ps1 -Target Copilot,Claude,Codex,Gemini
```

Mode selection:

```powershell
.\autoplan-dynamics-skills\scripts\Install-Skills.ps1 -Mode Symlink
.\autoplan-dynamics-skills\scripts\Install-Skills.ps1 -Mode Copy
```

`-Mode Auto` is the default: symlink when possible, otherwise copy.

## Uninstall

```powershell
.\autoplan-dynamics-skills\scripts\Uninstall-Skills.ps1
```

Multi-agent uninstall:

```powershell
.\autoplan-dynamics-skills\scripts\Uninstall-Skills.ps1 -Target Copilot,Claude
```
