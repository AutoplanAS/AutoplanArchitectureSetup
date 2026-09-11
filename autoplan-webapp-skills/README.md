# Autoplan lightweight webapp skills

This package contains a core, installable skillset for designing, planning, developing, testing, and deploying lightweight web applications using the same architecture and patterns as VehiclePortal.

## Included skills

- `autoplan-webapp-architecture`
- `autoplan-webapp-frontend-react`
- `autoplan-webapp-api-node`
- `autoplan-webapp-auth-data`
- `autoplan-webapp-testing-quality`
- `autoplan-webapp-deployment-hybrid`

## Skill format

Each skill follows the portable agent-skill layout:

- `skills/<skill-name>/SKILL.md`
- `skills/<skill-name>/references/*.md`

`SKILL.md` is the task-facing instruction entrypoint. `references/` contains deeper implementation guidance.

## Install

Run from repository root:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1
```

Default target:

```text
~\.agents\skills
```

Other agents:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Target Claude
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Target Copilot,Claude,Codex,Gemini
```

Mode selection:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Mode Symlink
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Mode Copy
```

`-Mode Auto` is the default: symlink when possible, otherwise copy.

## Uninstall

```powershell
.\autoplan-webapp-skills\scripts\Uninstall-Skills.ps1
```

Multi-agent uninstall:

```powershell
.\autoplan-webapp-skills\scripts\Uninstall-Skills.ps1 -Target Copilot,Claude
```
