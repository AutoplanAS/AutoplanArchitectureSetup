# Report template

Keep it short enough to read in one sitting. Findings, evidence, fix — nothing else.

⛔ Never paste a secret value into a report. Key name and value length only.

---

```markdown
# Integration review — <RepoName>

**Reviewed:** <date> · **Against:** Autoplan house standard (reference: EchoesIntegration)
**Function apps reviewed:** <project names>

## Verdict

<One paragraph. Overall health, and the single most important thing to do next.>

| Severity | Count |
|---|---|
| ⛔ Critical | n |
| ⚠️ High | n |
| Medium | n |
| Low | n |

## ⛔ Critical

### 1. <Title>

**Where:** `path/to/file.ext` line n
**What:** <what is actually there — quote it if short>
**Why it matters:** <consequence, concretely>
**Fix:** <the specific change>
**Skill:** `<skill-name>` → `references/<file>.md`

## ⚠️ High
<same shape>

## Medium
<same shape>

## Low
<one line each is fine>

## Conformance summary

| Check | Status | Note |
|---|---|---|
| Secrets not committed | ✅ / ⛔ | |
| `.gitignore` covers `local.settings.json` | ✅ / ❌ | |
| Config validated at startup | ✅ / ❌ | |
| Resilience on all HTTP clients | ✅ / ❌ | n of m clients |
| 401 handled | ✅ / ❌ / n/a | |
| Token cache is singleton | ✅ / ❌ / n/a | |
| Tests exist | ✅ / ❌ | n test projects |
| Tests run in CI | ✅ / ⛔ | |
| Pipeline present | ✅ / ❌ | |
| IaC present | ✅ / ❌ | |
| Central package management | ✅ / ❌ | |
| `NuGet.config` present | ✅ / ❌ | |
| Telemetry standard | OTel / App Insights | |

## Recommended order

1. **Rotate and remove** <credential> — nothing else until this is done.
2. ...

## Worth checking
<Leads that were not verified. Say plainly that they are unverified.>
```

---

## Writing the findings

**Quote what is there.** "No config validation" is an assertion; a three-line quote of the
`Configure<T>()` call is evidence.

**State the consequence, not the rule.** Not "violates the standard" but "a missing setting becomes
an empty string and surfaces as a 401 from the vendor hours later".

**One fix per finding, specific enough to act on.** "Improve error handling" is not a fix.

**Group Low findings.** Six repos drifting to App Insights is one migration, not six findings.

## Verdict paragraph

Say the most important thing first. Compare:

> The repository broadly follows the house standard with some deviations in configuration handling
> and telemetry.

versus:

> `local.settings.json` is committed with a live production username and password — rotate the
> credential before anything else. Beyond that the integration is structurally sound: options are
> validated at startup, the pipeline deploys both infra and app, and the only other gaps are a
> 455-line API client mixing HTTP with domain logic, and no test execution in CI.

The second is the same information, ordered by what the reader must do.

## When there is nothing to report

Say so plainly and list what you checked. A clean review is a useful result, and the check list is
what makes it credible.
