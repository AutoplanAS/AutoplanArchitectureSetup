# Check catalogue

Run in order. Security first — a leaked credential outranks everything below it.

Every command assumes `$repo` is the repository root and that you have identified the **function
project** (the `.csproj` referencing `Microsoft.Azure.Functions.Worker`). A repo may contain several;
check each.

⚠️ Read [false-positives.md](false-positives.md) before reporting anything from these commands.

## S1 ⛔ Committed secrets

```powershell
cd $repo
git ls-files | Where-Object {
  $n = Split-Path $_ -Leaf
  $n -eq "local.settings.json" -or $n -eq "appsettings.Development.json" -or
  $n -eq ".env" -or $n -like "*.bicepparam" -or $n -like "*.publishsettings"
}
```

Exact filename match — `local.settings.json.template` is correct practice, not a leak.

For each hit, inspect **key names and value lengths only**:

```powershell
git show "HEAD:<path>" | ForEach-Object {
  if ($_.Trim() -match '^"([^"]+)"\s*:\s*"(.*)"') {
    "{0} = {1}" -f $matches[1], $(if($matches[2]){"<len " + $matches[2].Length + ">"}else{"(empty)"})
  }
}
```

Empty values are a template and fine. Non-empty values under a key named `Password`, `Secret`,
`Key`, `Token`, `ConnectionString` or `AccessToken` are a leak.

⚠️ `*.bicepparam` files almost always appear in this list and are usually **fine**. OFV's
`parameters.dev.bicepparam` and `parameters.prod.bicepparam` are tracked, but declare
`ofvPassword = ''` with the value injected at deploy time — correct practice. Inspect before
reporting; only a non-empty secret literal is a finding.

Also scan source for literals:

```powershell
Get-ChildItem $repo -Recurse -Include *.cs,*.json,*.bicep,*.yml |
  Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' } |
  Select-String -Pattern '(?i)(password|secret|apikey|access_?token)\s*[:=]\s*"[^"]{8,}"'
```

**Fix:** rotate first, then `git rm --cached`, add the ignore rule and a `.example` file in the same
commit. → `autoplan-integration-auth/references/secrets-management.md`

## S2 ⛔ `.gitignore` coverage

```powershell
Get-Content "$repo\.gitignore" | Select-String "local.settings.json"
```

Must be present **and** S1 must be clean. Either alone is insufficient — an ignore rule added after
the file was tracked changes nothing.

## S3 ⚠️ Secrets in logs

```powershell
Select-String -Path (Get-ChildItem $repo -Recurse -Filter *.cs).FullName `
  -Pattern 'Log\w+\(.*(token|secret|password|apikey|header)' -CaseSensitive:$false
```

Also look for whole-header or whole-body dumps:

```powershell
Select-String -Path ... -Pattern 'foreach.*req\.Headers|LogHeaders'
```

Known: `DriveFunctions/DriveOrderHttpTrigger.cs` calls `LogHeaders(req)` **before** the auth check,
writing the shared secret to logs.

## S4 ⚠️ Anonymous endpoints

```powershell
Select-String -Path ... -Pattern 'AuthorizationLevel\.Anonymous'
```

Exclude test projects. Every hit in production code needs a justification comment plus a second auth
mechanism in the handler body.

## S5 ⚠️ `@secure()` on secret Bicep parameters

```powershell
Select-String -Path (Get-ChildItem $repo -Recurse -Filter *.bicep).FullName `
  -Pattern 'param \w*(password|secret|key|token|connectionstring)' -CaseSensitive:$false -Context 1,0
```

Every such parameter needs `@secure()` on the preceding line.

---

## C1 ⚠️ Configuration validated at startup

⚠️ DI wiring may live in an extension method rather than `Program.cs` (HubSpot does this). Search the
whole function project, excluding tests:

```powershell
Get-ChildItem $repo -Recurse -Include *.cs |
  Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' -and $_.FullName -notmatch '\.Tests\\' } |
  Select-String 'AddOptions|Configure<|ValidateOnStart'
```

Expect `AddOptions<T>().Bind(...).Validate(...).ValidateOnStart()`. `Configure<T>()` alone is a
finding: a missing setting then surfaces as a 401 hours later instead of a boot failure.

**Fix:** → `autoplan-integration-scaffold/references/configuration.md`

## C2 ⚠️ Resilience on every outbound client

Count across the whole function project, not just `Program.cs`:

```powershell
$src = Get-ChildItem $repo -Recurse -Include *.cs |
  Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' -and $_.FullName -notmatch '\.Tests\\' }
"AddHttpClient:  " + ($src | Select-String 'AddHttpClient').Count
"Resilience:     " + ($src | Select-String 'AddStandardResilienceHandler').Count
```

Counts should match. Fewer resilience handlers than clients means some client has no timeout,
retry or circuit breaker.

Verified state: Echoes 2/2. Every other repo has 0 resilience handlers — Easypark 3 clients,
Autoplan API / Drive / SmartCar / OFV 1 each.

Also flag **named** clients (`AddHttpClient("Name")`, as in HubSpot's
`ServiceCollectionExtensions.cs:34`) — they lose the compile-time link between client and config.
Prefer `AddHttpClient<IFooClient, FooClient>`.

And direct instantiation, which bypasses the factory entirely:

```powershell
$src | Select-String 'new HttpClient\('
```

**Fix:** → `autoplan-external-api-client/references/resilience.md`

## C3 Medium — token cache lifetime

```powershell
Select-String -Path ... -Pattern 'AddScoped|AddTransient' -Context 0,1 |
  Select-String -Pattern '(?i)token|auth|key.*provider'
```

Any token/key provider registered `AddScoped` or `AddTransient` mints a fresh credential per call.
Must be `AddSingleton`.

Also flag a token cached in an instance field of a client (`private string? _token`), which is the
same bug wearing a different hat — Easypark's `EasyparkApiClientBase`.

## C4 Medium — 401 handling

For each API client, confirm one of:

- a `DelegatingHandler` that invalidates and retries once, or
- an explicit `if (response.StatusCode == HttpStatusCode.Unauthorized)` branch that invalidates.

```powershell
Select-String -Path ... -Pattern 'Unauthorized|InvalidateToken|Invalidate\(\)'
```

No hits, in a client whose credential expires, means a rotated credential fails every call until
redeploy.

If a retry exists, verify the request is **cloned** before the first send — otherwise POST bodies are
lost on retry. → `autoplan-integration-auth/references/expiring-keys.md`

## C5 Medium — cancellation tokens

```powershell
Select-String -Path ... -Pattern 'public async Task' | Select-String -NotMatch 'CancellationToken'
```

Public async methods on clients and services should accept and forward a `CancellationToken`.

---

## D1 ⛔ Tests actually execute

```powershell
$ado = Get-ChildItem $repo -Recurse -Filter "azure-pipelines*.yml" -ErrorAction SilentlyContinue
$gha = Get-ChildItem (Join-Path $repo ".github\workflows") -Filter *.y*ml -ErrorAction SilentlyContinue

if ($ado) {
  .\scripts\Check-PipelineTestEnforcement.ps1 -Path $repo
}
if ($gha) {
  .\scripts\Check-GitHubWorkflowTestEnforcement.ps1 -Path $repo
}
```

⛔ Critical when CI reports test publishing or deploy readiness while no live test step executes.

For Azure DevOps, `DeadTest > 0` with `LiveTest > 0` is usually an explanatory comment above a
working step (Echoes). Read it before reporting.

## D2 ⚠️ Pipeline and IaC exist

```powershell
$ado = Get-ChildItem $repo -Recurse -Filter "azure-pipelines*.yml" -ErrorAction SilentlyContinue
$gha = Get-ChildItem (Join-Path $repo ".github\workflows") -Filter *.y*ml -ErrorAction SilentlyContinue

$ado | Select-Object FullName
$gha | Select-Object FullName
Get-ChildItem $repo -Recurse -Filter "*.bicep"
```

No CI workflow plus no IaC, in a deployed integration, is High. CI may be Azure DevOps or GitHub
Actions; either is acceptable if deploy controls are equivalent. Confirm deployment is not
centralised elsewhere before asserting.

## D3 Low — artifact separation

The pipeline should publish the function app zip and the infra templates as **separate artifacts**,
so a config-only change can be redeployed without rebuilding.

## D4 ⛔ Deploy stages gated on build reason

```powershell
$ado = Get-ChildItem $repo -Recurse -Filter "azure-pipelines*.yml" -ErrorAction SilentlyContinue
$gha = Get-ChildItem (Join-Path $repo ".github\workflows") -Filter *.y*ml -ErrorAction SilentlyContinue

if ($ado) {
  .\scripts\Check-PipelineDeployGating.ps1 -Path $repo
}
if ($gha) {
  .\scripts\Check-GitHubWorkflowDeployGating.ps1 -Path $repo
}
```

Azure DevOps: every `Deploy*` / `Update*Config` stage condition must begin with
`ne(variables['Build.Reason'], 'PullRequest')`.

GitHub Actions: every deploy job must gate on
`github.event_name != 'pull_request'` and a default-branch guard.

Without these guards, pull request validation can deploy pull request code to production.

⛔ Critical when the repo has, or is about to get, PR validation. Report it as Critical regardless,
because it also means any manual queue on any branch reaches prod.

Check the paired control before downgrading severity: an approval on the `-prod` environment would
contain the blast radius. In this project **none of the twelve environments has one** (verified
2026-08-19), so there is no compensating control.

```powershell
az devops invoke --org $org --area distributedtask --resource environments `
  --route-parameters project=$proj --api-version 7.1 --query 'value[].{id:id,name:name}'
```

---

## T1 ⚠️ Central package management

```powershell
Get-ChildItem $repo -Recurse -Filter Directory.Packages.props
Select-String -Path (Get-ChildItem $repo -Recurse -Filter *.csproj).FullName -Pattern 'Version='
```

Expect one `Directory.Packages.props` and **no** `Version=` attributes in any `.csproj`. Version
drift between repos is what the central file exists to prevent.

## T2 ⚠️ `NuGet.config` present

```powershell
Get-ChildItem $repo -Recurse -Filter NuGet.config
```

Required. Without `<clear/>` plus an explicit nuget.org source, the Functions Worker SDK's generated
`WorkerExtensions` inner restore fails on clean CI agents.
→ `autoplan-integration-scaffold/references/known-issues.md`

## T3 Medium — client size and responsibility

```powershell
Get-ChildItem $repo -Recurse -Filter *.cs |
  Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' } |
  Sort-Object { (Get-Content $_.FullName).Count } -Descending | Select-Object -First 5 |
  ForEach-Object { "{0,5}  {1}" -f (Get-Content $_.FullName).Count, $_.Name }
```

Open the top hits. Long DTO files are fine; long **clients** and **services** are the finding. Name
the distinct responsibilities you found mixed together.

## T4 Low — folder layout

Expect `Api/`, `Http/`, `Services/`, `Entities/`, `Models/`, `Configuration/`, `Functions/`, `infra/`,
`*.Tests/`. → `autoplan-integration-scaffold/references/project-layout.md`

---

## O1 Low — telemetry standard

```powershell
$p = Get-Content <Program.cs> -Raw
"OpenTelemetry: " + ($p -match 'OpenTelemetry')
"AppInsights:   " + ($p -match 'AddApplicationInsightsTelemetryWorkerService')
```

Standard is OpenTelemetry exporting to Application Insights when a connection string is present.
Also check `host.json` for `"telemetryMode": "OpenTelemetry"`.

Low severity: it works either way. Batch these into a single migration rather than raising one per
repo.
