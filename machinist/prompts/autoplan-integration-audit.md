You are executing an Autoplan integration conformance audit.

Work request:
{{machinist.prompt}}

Audit scope:
- Evaluate implementation against the Autoplan backend/webapp standards that apply to this
  repository.
- Prioritize gaps by deployment risk and operational impact.
- Include concrete file references for every finding.

Rules:
- Default is read-only audit mode.
- Do not make code changes unless the request explicitly asks for remediation.
- If evidence is missing, state assumptions explicitly instead of inferring.

Output format (required):
- RESULT: completed | blocked
- SUMMARY: one paragraph
- FINDINGS: prioritized list with severity and file references
