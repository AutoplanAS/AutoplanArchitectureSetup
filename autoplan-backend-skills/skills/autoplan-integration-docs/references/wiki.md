# The platform wiki

`Autoplan-API-Platform.wiki` is an Azure DevOps wiki repo. Its entire contents:

```
.gitignore                    0 bytes
.order                       13 bytes
Intro-%2D-tbe.md              0 bytes
Intro-%2D-tbe/.order          7 bytes
Intro-%2D-tbe/GraphQL.md      0 bytes
```

**Every markdown file is zero bytes.** The page structure was created and never filled in. The
`%2D` in the filename is a URL-encoded hyphen, which is how Azure DevOps stores page titles
containing `-`.

## What belongs here rather than in a repo

The split is: **a repo documents itself; the wiki documents everything that spans repos.**

Anything that is true of one integration goes in that integration's `readme.md` or
`DOCUMENTATION.md`. Duplicating it here creates a second copy that will disagree with the first.

Candidate wiki content, none of which currently has a home:

### 1. The integration catalogue

One table. For each integration: what it connects, direction of data flow, trigger schedule, owner,
where it deploys. Today the only way to answer "what integrations do we have and what do they do" is
to open eight repositories.

### 2. The house architecture

The shared pattern that every integration follows -- isolated worker Azure Functions on .NET 8,
consumption plan, timer or HTTP triggers, typed `HttpClient` per external API, services holding the
logic, Table Storage for state, Bicep for infra, five-stage Azure DevOps pipeline.

This is exactly what the skills in this repo encode, so the wiki page should be short and point at
them rather than restate them.

### 3. Shared external systems

Autoplan's own SQL database, the shared data storage account, the Vercel Vehicle API. Each is used
by more than one integration, so no single repo is the right home. Connection details belong in Key
Vault, not here -- see `autoplan-azure-deploy/references/gaps.md`.

### 4. Environments and access

Which subscriptions, which resource groups, the `<integration>-dev` / `<integration>-prod`
environment naming, who approves a prod deployment, how to get a service connection. New joiners ask
these first and there is currently nowhere to point them.

### 5. Operational runbook

What to do when an integration stops. Where the logs are (Application Insights per integration), how
to trigger a manual run, who to contact for each vendor API.

Worth writing down now: **timer-triggered integrations fail silently.** The two metric alerts in
every Bicep template are `Http5xx` and `AverageResponseTime`, which a timer-triggered function can
never trip, and no template supplies an action group. Nothing pages anyone. Until that is fixed, the
runbook is "someone notices the data is stale", and that should be written down honestly rather than
left implied.

### 6. Known issues across the estate

The findings in `docs/roadmap.md` -- HubSpot deals not reaching SQL, Drive's dropped
`ForhandlerNavn`/`ForhandlerNummer`, the disabled test steps, `local.settings.json` committed with
live OFV credentials. These span repos and each needs an owner.

## Suggested page tree

```
Home
├── Integration catalogue
├── Architecture
│   ├── House pattern
│   ├── Data flow
│   └── Copilot skills (link to AutoplanCopilotSkills)
├── Environments and access
├── Shared systems
│   ├── Autoplan SQL
│   ├── Shared data storage
│   └── Vercel Vehicle API
├── Operations
│   ├── Runbook
│   ├── Monitoring and alerting
│   └── Deployment and rollback
└── Known issues
```

## If you write it

- **Link, do not copy.** A wiki page that restates a repo's `DOCUMENTATION.md` will be wrong within
  a quarter. Link to the file in the repo.
- **Date anything that is a snapshot.** "As of 2026-08: six integrations deployed, three run tests in
  CI." A snapshot with a date ages honestly; one without ages into a lie.
- **Same verified-versus-assumed discipline as the repo docs.** See
  [api-documentation.md](api-documentation.md).
- **Delete the empty placeholder pages** (`Intro-%2D-tbe`, `GraphQL`) rather than leaving them. An
  empty page in a navigation tree reads as "this exists but is broken".
