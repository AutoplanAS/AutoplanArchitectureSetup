---
name: autoplan-webapp-deployment-hybrid
description: Deploy lightweight web apps using the Autoplan hybrid baseline: frontend on Vercel and API on Azure App Service with Azure SQL and explicit runtime verification.
license: Proprietary - Autoplan internal use
metadata:
  owner: Autoplan
  source-repo: JoergenAmrudHagen/VehiclePortal
  lifecycle: deploy-operate
---

# Autoplan hybrid deployment skill

Use this skill when deploying or operating lightweight web apps in a split-host setup.

## Baseline topology

1. Frontend build hosted by Vercel.
2. Node API hosted by Azure App Service.
3. Azure SQL for persistence.
4. API base URL configured in frontend env.
5. API CORS configured for frontend origin.

## Deployment sequence

1. Apply infrastructure (`infra/main.bicep`, parameters file).
2. Deploy API and configure runtime settings.
3. Configure frontend environment (`REACT_APP_API_BASE_URL`).
4. Validate health, version, telemetry, and core auth/data flow.

## Operational rules

1. Runtime config in host environment, not only local files.
2. Verify deployed commit/version through API endpoint.
3. Keep telemetry enabled and validated.
4. Keep SQL connectivity path stable before traffic cutover.

Read `references/vercel-and-appservice.md` first, then `references/release-runbook.md`.

