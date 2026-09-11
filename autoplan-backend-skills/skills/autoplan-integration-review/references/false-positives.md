# False positives — read before reporting

Every check in this skill has been run against all seven repos. These are the ways they lied. Each
one produced a wrong answer during the review that built this skill.

**The rule: a grep hit is a lead, not a finding.** Open the file.

## 1. Repo-wide grep says every repo is compliant

Running this across a whole repo:

```powershell
Get-ChildItem $repo -Recurse -Include *.cs,*.yml |
  Select-String 'ValidateOnStart|AddStandardResilienceHandler|OpenTelemetry' -Quiet
```

returned `True` for **all six** repos. The true answer:

| Repo | ValidateOnStart | Resilience | OpenTelemetry |
|---|---|---|---|
| Echoes | ✅ | ✅ | ✅ |
| Autoplan API | ✅ | ❌ | ✅ |
| Drive (DriveFunctions) | ✅ | ❌ | ❌ |
| Drive (SmartCar) | ❌ | ❌ | ❌ |
| OFV | ✅ | ❌ | ✅ |
| Easypark | ❌ | ❌ | ❌ |
| HubSpot | ❌ | ❌ | ❌ |

The hits came from README files, migration notes, pipeline comments, and test code that *names* the
pattern without using it. Documentation describing an intention reads exactly like an
implementation.

**Do instead:** read the function project's **composition root** — `Program.cs` plus any DI
extension methods it calls (see #2 below).

```powershell
Get-ChildItem $repo -Recurse -Filter Program.cs |
  Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' }
```

## 2. DI wiring is not always in `Program.cs`

HubSpot's `Program.cs` contains **zero** `AddHttpClient` calls. Concluding "no HTTP client" would be
wrong — the registration lives in an extension method:

```csharp
// HubSpotDataRetriever/ServiceCollectionExtensions.cs:34
services.AddHttpClient("HubSpot");
```

Follow the calls out of `Program.cs` before concluding anything is missing:

```powershell
Get-ChildItem $repo -Recurse -Include *.cs |
  Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' } |
  Select-String 'AddHttpClient|AddSingleton|AddOptions|ValidateOnStart' |
  Where-Object { $_.Path -notmatch '\.Tests\\' }
```

That hit also shows a **named** client (`AddHttpClient("HubSpot")`) rather than a typed one, resolved
later through `IHttpClientFactory`. Named clients are a separate finding — they lose compile-time
binding between the client and its configuration.

## 3. A repo can have more than one `Program.cs`

Drive Integration has two function apps (`DriveFunctions`, `SmartCarIntegration`) with different
conformance. HubSpot has a `samples/ConsoleSample/Program.cs` that is not a function app at all.

Reporting one verdict per repo is wrong. **Report per function app.** Exclude `samples/`, `bin/`,
`obj/`, and test projects.

## 4. `local.settings.json` matches `local.settings.json.template`

```powershell
git ls-files | Select-String "local.settings.json"     # WRONG
```

flagged HubSpot, which is actually doing the right thing: it commits
`local.settings.json.template` with empty secret values and git-ignores the real file. Reporting
that as a leak destroys trust in the whole report.

```powershell
git ls-files | Where-Object { (Split-Path $_ -Leaf) -eq "local.settings.json" }   # correct
```

Then confirm it really holds secrets — an ignore rule may have been added *after* the file was
tracked, so `git check-ignore` succeeding does not mean the file is untracked:

```powershell
git show "HEAD:<path>"
```

⛔ When printing findings, print **key names and value lengths**, never values. A review that pastes
the credential into a report has leaked it again.

## 5. `.gitignore` covering a file that is already tracked

`.gitignore` has no effect on tracked files. A repo can have a perfect ignore rule and still commit
the secret on every change.

Both must hold: an ignore rule exists **and** `git ls-files` does not list the file. OFV fails the
first; a repo that added the rule late fails only the second, which is the easier one to miss.

## 6. "Has tests" is not "runs tests"

A repo can have a test project, a test task, and a green pipeline, and execute nothing:

| Repo | Test project | Test step | Publishes results |
|---|---|---|---|
| Echoes | ✅ | ✅ `bash: dotnet test` | ✅ |
| Drive | ✅ | ✅ `DotNetCoreCLI@2 test` | ✅ |
| HubSpot | ✅ | ✅ `DotNetCoreCLI@2 test` | ✅ |
| Easypark | ✅ | ⛔ **commented out** | ✅ |
| OFV | ✅ | ❌ none | ❌ none |

Check three things separately: a test project exists, a **non-commented** test step exists, results
are published. Easypark has 1 and 3 but not 2 — the worst combination, because the build looks green.

YAML comments are `#`, so a commented task still matches a naive `dotnet test` grep:

```powershell
$lines | Where-Object { $_ -match 'dotnet test' -and $_ -notmatch '^\s*#' }
```

Also match `command: 'test'` — `DotNetCoreCLI@2` never contains the string `dotnet test`. Checking
only one form misses whole repos.

## 7. Echoes has a commented-out `dotnet test` too — and it is correct

Echoes matches "commented dotnet test" **and** "live dotnet test". The comment is an explanation
above the working step:

```yaml
# NOTE: The Functions Worker SDK restores a generated WorkerExtensions
# project during the *build* phase. The DotNetCoreCLI@2 'test' command
# does not supply the NuGet config that its 'restore' command injects,
# ...
- bash: |
    dotnet test "$(testProjectPath)" \
```

A commented mention is only a finding when there is **no** live equivalent. Count both, compare.

## 8. Line count is not complexity

`SalesContractEntity.cs` is 928 lines and `Types.cs` is 1085 — both are generated-style DTO
declarations. They are fine.

`OFVApiClient.cs` at 455 lines is a genuine finding because it mixes HTTP, auth, parsing and domain
logic in one class.

**Open the file and look at what the lines are.** Long DTOs are not debt; long *clients* and long
*services* are. Never report a size finding without naming the distinct responsibilities you found.

## 9. `AuthorizationLevel.Anonymous` in a test or a sample

Test fixtures construct triggers with anonymous level. Restrict the check to the function project,
and confirm the hit sits on an `[HttpTrigger(...)]` attribute in non-test code.

## 10. Absence of a file is not absence of the capability

Autoplan API has no CI workflow (`azure-pipelines.yml` or `.github/workflows/*.yml`) and no Bicep —
a real finding. But before reporting "no IaC", check whether deployment is centralised elsewhere (a
shared pipeline repo, a platform team's template). Ask rather than assert when the repo is
otherwise mature.

## Reporting standard

For each finding, state:

1. the file and line you **opened**,
2. what you saw there,
3. why it is a problem,
4. the fix.

If you cannot supply all four, it is a lead and belongs under "worth checking", not in the findings
table.
