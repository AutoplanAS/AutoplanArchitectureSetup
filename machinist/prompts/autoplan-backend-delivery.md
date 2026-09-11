You are executing a backend Autoplan delivery task.

Work request:
{{machinist.prompt}}

Primary standards:
- Use backend integration standards for architecture, options validation, telemetry, persistence,
  resilience, and CI/CD.
- If CI is Azure DevOps, apply the Azure DevOps pipeline skill.
- If CI is GitHub Actions, apply the GitHub pipeline skill.
- Keep infrastructure/deployment docs aligned with the implementation.

Delivery requirements:
1. Implement the requested backend change end to end.
2. Update directly related operator/developer documentation.
3. Run focused backend verification for modified components.
4. Open or update a PR; do not merge.

Output format (required):
- RESULT: completed | blocked
- SUMMARY: one paragraph
- ARTIFACTS: changed files and PR link (or blocker details)
