# Keep or discard

## The test

Ask: **will this sentence still be true and useful in six months?**

- "The Echoes API returns 200 with an empty body when a VIN is unknown" -- true forever. Keep, in
  `DOCUMENTATION.md` section 2.
- "I updated SaveCompaniesAsync to remove five parameters" -- describes one commit. Discard; it is
  the commit message.

Documents that describe **the state of the system** belong in the repo. Documents that describe
**an act of changing it** belong in git history and pull requests.

## The names to refuse

If a filename matches any of these, it is episodic:

```
*_SUMMARY.md          *_FIX.md              *_UPDATE.md
*_UPDATES.md          *_STATUS_REPORT.md    COMPLETION_*.md
*_VERIFICATION.md     *_COMPARISON.md       *_REFACTORING_*.md
FINAL_*.md            *_CHANGE.md
```

These proliferate when an AI assistant is asked to make a change and writes a report afterwards.
That report is useful **in the conversation**. It is not useful in the repository, where it will
outlive its accuracy by years.

## What it costs

`Hubspot Integration` root:

| File | Lines |
|---|---|
| `COMPLETION_SUMMARY.md` | 364 |
| `FINAL_STATUS_REPORT.md` | 326 |
| `UPDATE_COMPLETION_VERIFICATION.md` | 319 |
| `DOCUMENTATION_INDEX.md` | 311 |
| `README_UPDATES.md` | 301 |
| `CONTACT_TICKET_VALIDATION.md` | 300 |
| `SQLDATABASESERVICE_UPDATE.md` | 295 |
| `CODE_COMPARISON.md` | 290 |
| `MODELS_UPDATE_SUMMARY.md` | 265 |
| `MAPPINGSERVICE_UPDATE.md` | 255 |
| `REFACTORING_SUMMARY.md` | 209 |
| `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md` | 200 |
| `TABLEENTITIES_UPDATE.md` | 199 |
| `CONFIGURATION_CHANGE.md` | 194 |
| `PROPERTYNAMES_UPDATE.md` | 183 |
| `SQL_PARAMETER_FIX.md` | 49 |
| `DEPLOYMENT_GUIDE.md` | 316 |
| `README.md` | 186 |

18 files, 4,562 lines. `Check-DocsHygiene.ps1` flags **14** of them as episodic by filename alone.
Of the four it does not flag: `README.md` is the real readme, `DOCUMENTATION_INDEX.md` is an index
of the sprawl, and `DEPLOYMENT_GUIDE.md` and `CONTACT_TICKET_VALIDATION.md` need a judgement call --
both contain durable material buried in change narrative.

Three distinct costs:

1. **Nobody can find the real documentation.** `README.md` is one file among eighteen, and the
   index file is 311 lines.
2. **They go stale silently.** Nothing rebuilds them and nothing checks them.
3. **They make false claims that stop people looking.** `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md`
   asserts `SqlDatabaseService.cs` was "recreated from scratch" with "correct parameter mappings".
   Lines 432-445 of that file still contain DDL pasted into a MERGE. The deals sync has been broken
   the whole time. Anyone who read the document concluded it was handled.

Note the first document, `SQL_PARAMETER_FIX.md`, was honest -- line 38 says the other save methods
"should be reviewed to ensure they only reference properties that exist". A later, longer, more
confident document buried that caveat. **Confidence in a document is not evidence.**

Several of these files also contain mojibake where an emoji was written and the encoding mangled it
(`? SaveCompaniesAsync MERGE statement corrected`). A `?` where a status marker should be is a
reliable tell that a document was machine-written and never re-read.

## Cleaning up

Work through them once. For each file:

1. **Extract anything durable** -- an API quirk, a schema decision, a rationale -- into the right
   section of `DOCUMENTATION.md`, rewritten in present tense as a statement about the system.
2. **Verify any claim of a fix against the code before you carry it forward.** Open the file, find
   the line. If the claim is false, the durable content is a *bug report*, not documentation --
   file it as a work item.
3. **Delete the file.** It is in git history if anyone needs it.

For HubSpot specifically, the durable content is roughly:

- `DEPLOYMENT_GUIDE.md` (316) -- mostly durable, merge into `readme.md` under `## Getting started`
  and `## CI/CD`.
- `docs/PropertyNamesAndTypedModels.md` (272) -- durable subsystem reference, keep as a `docs/` file.
- The HubSpot property-name mappings scattered across `PROPERTYNAMES_UPDATE.md`,
  `MODELS_UPDATE_SUMMARY.md` and `TABLEENTITIES_UPDATE.md` -- consolidate into
  `DOCUMENTATION.md` section 5.
- The SQL parameter material -- **do not carry the completion claim forward.** The bug is live.

Expected outcome: 18 files to 2 root files plus a `docs/` folder.

## Writing the change up instead

Everything these files were trying to do is better served by:

- **The commit message.** What changed and why. This is the durable record and it is attached to the
  diff.
- **The pull request description.** Context, testing performed, risks.
- **A work item.** For anything unfinished. `SQL_PARAMETER_FIX.md:38` identified real remaining work;
  as a markdown file it was invisible, and as a work item it would have been assigned.

If you are asked to "document what you changed", the answer is a good commit message. If the change
altered how the system behaves, also update the relevant section of `DOCUMENTATION.md` -- in place,
in present tense, as a description of how it works now.

## Detecting it

```powershell
.\scripts\Check-DocsHygiene.ps1 -Path <repo>
```

Flags episodic filenames, the untouched Azure DevOps README template, missing `DOCUMENTATION.md`,
and zero-byte markdown.
