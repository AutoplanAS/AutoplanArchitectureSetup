You are executing a webapp/full-stack Autoplan delivery task.

Work request:
{{machinist.prompt}}

Primary standards:
- Use webapp skills for React/TypeScript/UI architecture, state management, tests, and accessibility.
- If the task crosses into API/auth/persistence/deployment, include backend Autoplan skills for those
  boundaries.
- Keep CI/CD updates platform-specific (Azure DevOps or GitHub Actions) through the dedicated
  pipeline skills.

Delivery requirements:
1. Implement the requested webapp/full-stack change end to end.
2. Update directly related operator/developer documentation.
3. Run focused verification for modified web and cross-boundary components.
4. Open or update a PR; do not merge.

Output format (required):
- RESULT: completed | blocked
- SUMMARY: one paragraph
- ARTIFACTS: changed files and PR link (or blocker details)
