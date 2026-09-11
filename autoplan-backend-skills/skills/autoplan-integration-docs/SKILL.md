---
name: autoplan-integration-docs
description: "Documentation for Autoplan integrations: the two-file standard (readme.md for operators, DOCUMENTATION.md for the full reference), what belongs in each section, the keep/discard rule that stops episodic AI-generated status reports accumulating in the repo root, verified-versus-assumed labelling, and seeding the platform wiki. WHEN: \"write the README\", \"document this integration\", \"DOCUMENTATION.md\", \"update the docs\", \"what should the readme say\", \"document the API\", \"decisions log\", \"summary document\", \"wiki\", \"too many markdown files\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration
---

# Autoplan Integration Docs

Two markdown files per integration, both at the repo root, both maintained:

- **`readme.md`** -- what an operator or a new developer needs to run and understand it. ~140 lines.
- **`DOCUMENTATION.md`** -- the full reference: verified API behaviour, schemas, architecture,
  decisions log. ~325 lines.

Reference: `EchoesIntegration/readme.md` (143 lines) and `EchoesIntegration/DOCUMENTATION.md` (325).
It is the only repo in the estate with both.

## Rules

1. **Two files, not eighteen.** Everything durable goes in one of the two. See
   [structure.md](references/structure.md).
2. **Never commit an episodic "what I just changed" document.** `*_SUMMARY.md`, `*_FIX.md`,
   `*_UPDATE.md`, `*_STATUS_REPORT.md`, `COMPLETION_*.md` -- that is what commit messages and pull
   requests are for. See [keep-or-discard.md](references/keep-or-discard.md).
3. **Label verified separately from assumed.** Echoes writes headings like *"Authentication (two
   tokens -- verified against the live API)"* and keeps a section 9 "Verification performed". A
   reader must be able to tell what someone actually observed from what someone expected.
4. **A document may not claim a fix it has not verified in the code.** This is the rule that the
   estate breaks most expensively -- see below.
5. **Keep a decisions log.** Section 11 of Echoes' `DOCUMENTATION.md`. One line per decision with the
   reason. It is the only part of the documentation that cannot be reconstructed by reading the code.
6. **Document the API you observed, not the API the vendor documented.** Undocumented quirks --
   `200` with an empty body, a fee record type that does not exist, a field that is a string
   sometimes and a number others -- are the highest-value content in the file.

## The rule 4 case

`Hubspot Integration` has **18 root-level markdown files, 4,562 lines.** Two of them are about the
SQL parameter bug:

- `SQL_PARAMETER_FIX.md` (49 lines)
- `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md` (200 lines)

The second is titled *"Complete Fix Report"* and states:

> ### 1. Recreated SqlDatabaseService.cs from scratch
> - Removed the corrupted file
> - Created a new clean version with correct parameter mappings

`SqlDatabaseService.cs:432-445` still contains raw DDL column definitions pasted into the
`UPDATE SET` clause of the deals MERGE:

```sql
AnalyticsLatestSourceData2 = @AnalyticsLatestSourceData2, ...
AnalyticsSource NVARCHAR(100), AllOwnerIds NVARCHAR(MAX), AllAccessibleTeamIds NVARCHAR(MAX),
```

The exception it throws is swallowed at `492-497`. HubSpot deals have never reached SQL.

Note that the *first* document was honest -- it says at line 38 that `SaveDealsAsync` "should be
reviewed". The second document overwrote that caveat with a claim of completeness that was never
checked. **A document asserting a state the code does not have is worse than no document**, because
it stops the next person looking.

If you write that something is fixed, the sentence needs a file and line reference, and you need to
have opened that file.

## Current state

Verified 2026-08-19:

| Repo | Root .md files | Lines | Assessment |
|---|---|---|---|
| Echoes | 2 | 468 | the standard |
| Drive | 1 + `docs/` (5) | 1,955 | good structure, 2 episodic files in `docs/` |
| Easypark | 1 | 20 | **untouched Azure DevOps default template**, all TODOs |
| AutoplanAPIIntegration | 1 | 20 | **untouched default template** |
| Vercel Vehicle API | 1 | 20 | **untouched default template** |
| OFV | 1 | **1** | a single `# OFVIntegration` heading |
| HubSpot | **18** | **4,562** | episodic sprawl, incl. a false completion claim |

The platform wiki (`Autoplan-API-Platform.wiki`) contains three markdown files. **All three are
zero bytes.** See [wiki.md](references/wiki.md).

```powershell
.\scripts\Check-DocsHygiene.ps1 -Path <repo>
```

## References

- [structure.md](references/structure.md) -- the two files, section by section, with Echoes' actual headings.
- [keep-or-discard.md](references/keep-or-discard.md) -- the rule for episodic documents, and how to clean up 18 of them.
- [api-documentation.md](references/api-documentation.md) -- documenting observed behaviour, verified-vs-assumed, the decisions log.
- [wiki.md](references/wiki.md) -- what belongs at platform level rather than in a repo, and seed content.
