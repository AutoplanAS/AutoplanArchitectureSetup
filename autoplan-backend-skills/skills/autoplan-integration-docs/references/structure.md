# Structure

Two files at the repo root. Both are maintained; neither is generated.

## `readme.md` -- the operator's file

What someone needs to run it, change a setting, or find out what it does. Echoes' headings, in order:

```
# Echoes Integration (Test)
## How it works
## Functions
### Timer-triggered
### HTTP-triggered (function key auth)
### Diagnostics (function key auth, read-only unless noted)
## Azure Table Storage
## Configuration
## Getting started
## Project structure
## CI/CD (Azure DevOps)
## Original scaffold notes (kept for history)
```

Notes on the choices:

- **`## How it works` is first and is prose.** Before any list of functions, three or four sentences
  saying what the integration is for and which direction data flows. This is the section people
  actually read.
- **Every function is listed with its trigger type and its auth.** `(function key auth)` in the
  heading, not buried in a table. Someone deciding whether an endpoint is safe to call needs it
  there.
- **Diagnostics endpoints get their own section, labelled "read-only unless noted".** These exist to
  be called by a human during an incident; hiding them among the business endpoints wastes time
  exactly when time matters.
- **`## Configuration` lists every app setting** with its purpose and whether it is a secret. This
  must match `infra/main.bicep` -- see `autoplan-azure-deploy/references/parameters-and-secrets.md`.
- **`## Original scaffold notes (kept for history)`** is the honest way to retain the template text
  that came with `func init`, rather than leaving it interleaved with real content. Three repos in
  the estate never did this and their README is *only* the template.

Target ~140 lines. If a section wants to grow past a screen, it belongs in `DOCUMENTATION.md`.

## `DOCUMENTATION.md` -- the reference

Echoes' headings, numbered so they can be cited in a conversation ("see section 5"):

```
# EchoesIntegration - Complete Documentation
## 1. Purpose and scope
## 2. The Echoes API (as verified against live Swagger)
### Authentication (two tokens - verified against the live API)
### Endpoints used
### Vehicle lifecycle (`deviceStatus`)
## 3. Architecture
### Desired-state reconciliation
### Odometer retrieval
## 4. Functions
### Timer-triggered
### HTTP-triggered (all use function-key authorization)
## 5. Azure Table Storage schema
### `EchoesVehicleState` (desired state, driven by you)
### `EchoesOdometerReadings` (output)
## 6. Configuration
## 6a. Diagnostics endpoints (manual testing)
## 7. Project structure
### Dependencies (NuGet)
## 8. How to run the test
## 9. Verification performed
## 10. Relation to the KM calculation project
## 11. Decisions log
```

The sections that carry weight:

- **2 -- the external API.** The most valuable section in the file, because it is the only place the
  vendor's actual behaviour is written down. See [api-documentation.md](api-documentation.md).
- **5 -- the storage schema,** with each table annotated by role: *"(desired state, driven by you)"*
  versus *"(output)"*. Whether a table is an input you control or an output you produce is the first
  thing anyone needs and the last thing anyone writes down.
- **9 -- verification performed.** What was actually run against the live system, and when. This is
  what makes the rest of the document trustworthy.
- **11 -- the decisions log.** The only content that cannot be recovered by reading the code.

Numbering survives editing better than it looks -- note `6a`, added rather than renumbering
everything below it. That is the right trade.

## Where a `docs/` folder fits

Drive uses one for material too long for `DOCUMENTATION.md`:

```
docs/DriveFunctions.md            275 lines
docs/VEHICLE_ENRICHMENT.md        685 lines
```

`VEHICLE_ENRICHMENT.md` at 685 lines is a genuine subsystem reference and belongs in a file of its
own. That is the legitimate use: **a durable deep-dive on one subsystem**, linked from
`DOCUMENTATION.md`.

It is not a place to put change reports. Drive's `docs/` also contains `GRAPHQL_SCHEMA_FIX.md` and
`ITERATION_ID_OPTIMIZATION.md`, which are episodic -- see
[keep-or-discard.md](keep-or-discard.md).

Drive and HubSpot both maintain a `DOCUMENTATION_INDEX.md` (319 and 311 lines). An index that long
is a symptom: it exists because there are too many files to navigate without one. Fix the sprawl
rather than indexing it.

## New integration checklist

- [ ] `readme.md` written -- **the default Azure DevOps template deleted, not left in place**
- [ ] `DOCUMENTATION.md` with sections 1-11
- [ ] Every app setting in `## Configuration` matches `infra/main.bicep`
- [ ] Section 2 records observed API behaviour, with quirks
- [ ] Section 9 says what was verified and when
- [ ] Section 11 started, even if it has one entry
- [ ] No `*_SUMMARY.md` / `*_FIX.md` / `*_STATUS_REPORT.md` at the root

```powershell
.\scripts\Check-DocsHygiene.ps1 -Path <repo>
```
