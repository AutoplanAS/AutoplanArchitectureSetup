# Issue-to-PR workflow

This workflow is the baseline execution path for using Machinist as a coding factory in this
repository.

## Flow

1. Submit a work request that points to a concrete issue (or equivalent scoped task).
2. Run `autoplan-factory-foreman`.
3. Foreman routes into backend, webapp, or generic blueprint behavior.
4. Worker implements changes and opens/updates a PR.
5. Human review and merge remain manual.

## Direct run (single request)

PowerShell:

```powershell
.\machinist\workflows\issue-to-pr\run-local.ps1 `
  -Prompt "Complete https://github.com/AutoplanAS/AutoplanArchitectureSetup/issues/123"
```

Bash:

```bash
./machinist/workflows/issue-to-pr/run-local.sh \
  --prompt "Complete https://github.com/AutoplanAS/AutoplanArchitectureSetup/issues/123"
```

## Managed queue mode

Use `machinist start` and `machinist worker start` with your configured files, then trigger intake
by applying labels configured in `machinist/config.toml`.
