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

## Install to Copilot CLI skills folder

Run from repository root:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1
```

By default, skills are copied into:

```text
~\.agents\skills
```

Custom target folder:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -TargetRoot "C:\Temp\skills"
```

Optional symlink mode:

```powershell
.\autoplan-webapp-skills\scripts\Install-Skills.ps1 -Mode link
```

## Uninstall

```powershell
.\autoplan-webapp-skills\scripts\Uninstall-Skills.ps1
```
