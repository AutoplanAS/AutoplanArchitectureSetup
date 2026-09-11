# Anti-patterns found in this codebase

Each is real, cited, and was found during the review that produced these skills. When you see one
in a new repo, it is a known problem with a known fix — not a judgement call.

## ⛔ Credentials committed to git

`OFVIntegration/local.settings.json` is tracked and `.gitignore` does not exclude it. It contains
`OFV__Username`, `OFV__Password` and `OFV__BaseUrl` with live values for a production endpoint.

Verified with `git ls-files` (lists it), `git check-ignore` (no rule) and `git show HEAD:...`
(non-empty values).

Everyone with repo read access has the credential, and it is in every clone and the full history.

**Fix:** rotate first — until then nothing else matters. Then `git rm --cached`, add the ignore rule
and a `local.settings.example.json` in the same commit, and decide explicitly whether to rewrite
history.

## ⛔ A control that reports success without doing anything

`EasyparkIntegration/EasyparkIntegration/azure-pipelines.yml`:

```yaml
59            #- task: DotNetCoreCLI@2
60            #  displayName: 'Test'
61            #  inputs:
62            #    command: 'test'
63            #    projects: '$(testProjectPath)'
64            #    arguments: '--configuration $(buildConfiguration) --logger trx ...'
65
66            - task: PublishTestResults@2
67              displayName: 'Publish test results'
68              condition: succeededOrFailed()
```

The test task is commented out; the publish task still runs. The build shows a green "Publish test
results" step for a test run that never happened. Worse than having no tests, because it reads as
covered.

**Fix:** re-enable the test step, or delete the publish step. Never leave only the second.

Contrast OFV, which has a test project and *neither* step — honest, and a lower severity.

## ⛔ A safety feature that would deploy production

All six pipelines gate their deploy stages on parameters and stage dependencies, but not on *why*
the build is running:

```yaml
- stage: DeployProdApp
  dependsOn: DeployDevApp
  condition: and(succeeded(), eq(${{ parameters.deployProdApp }}, true))
```

`deployDevInfra` and `deployProdInfra` both `default: true`. So the pipeline deploys to production on
any run that reaches the stage — including a Build Validation run, which executes the whole YAML
against the pull request merge commit.

The trap is that this only bites when someone does the *responsible* thing. The repos had no PR
validation, which was correctly filed as a gap. Acting on that gap in the obvious way — turning on
validation — would have turned every pull request into a production deployment. The remediation and
the latent defect were individually reasonable and jointly catastrophic.

**Fix:** gate first, then enable validation. Never the reverse.

```yaml
  condition: and(ne(variables['Build.Reason'], 'PullRequest'), succeeded(), eq(${{ parameters.deployProdApp }}, true))
```

**Generalisation worth carrying:** before enabling any control that causes a pipeline to run in a new
context, enumerate what that pipeline *does* when it runs. Ask what the new trigger executes, not
just what it checks.

## ⚠️ Configuration bound without validation

Easypark, HubSpot and SmartCar bind options with `Configure<T>()` and no `.Validate().ValidateOnStart()`.
A missing setting becomes an empty string, which becomes a 401 from the vendor hours later.

SmartCar skips the options system entirely:

```csharp
_clientId = Environment.GetEnvironmentVariable("SMARTCAR_CLIENT_ID") ?? string.Empty;
```

No validation, no `IOptions<T>`, no startup failure — `?? string.Empty` converts a configuration
error into a runtime auth error.

**Fix:** `AddOptions<T>().Bind(...).Validate(...).ValidateOnStart()`. ⛔ Never default a secret.

## ⚠️ Outbound HTTP with no resilience

Only Echoes calls `AddStandardResilienceHandler` (2 clients, 2 handlers). Every other function app
has zero — Easypark registers 3 clients, Autoplan API, Drive, SmartCar and OFV one each. A slow
vendor stalls the function until the 100-second `HttpClient` timeout, with no retry, no circuit
breaker and no per-attempt timeout.

HubSpot hand-rolled its own retry with `MaxRetries` and `InitialBackoffSeconds` settings — the
problem was understood, the standard solution was not applied. It also registers a **named** client
(`services.AddHttpClient("HubSpot")` in `ServiceCollectionExtensions.cs:34`) rather than a typed one,
so the client and its configuration are only linked by a string.

**Fix:** typed clients, each with `AddStandardResilienceHandler`.

## Medium — token cached per client instance

`EasyparkIntegration/Api/EasyparkApiClientBase.cs`:

```csharp
private string? _token;

protected async Task<string> EnsureTokenAsync(CancellationToken cancellationToken)
{
    _token ??= await LoginAsync(cancellationToken);
    return _token;
}
```

Two bugs. Each client instance logs in separately, so the login endpoint is hit far more than
needed. And `??=` never refreshes: once the token expires, every call 401s forever.

**Fix:** singleton provider plus a `DelegatingHandler` that invalidates and retries once.

## Medium — no 401 handling

OFV and HubSpot never inspect `HttpStatusCode.Unauthorized`. A rotated or expired credential fails
every call until someone redeploys.

## Medium — the monolithic client

`OFVIntegration/Services/OFVApiClient.cs` is 455 lines carrying HTTP calls, auth, response parsing
and domain logic in one class. Nothing can be tested without the HTTP layer.

Distinguish this from long DTO files (`SalesContractEntity.cs` at 928 lines, `Types.cs` at 1085) —
those are declarations and are fine.

**Fix:** split into `Api/` (HTTP and DTOs) and `Services/` (domain logic).
→ `autoplan-integration-scaffold/references/project-layout.md`

## Medium — secrets reachable from logs

`DriveFunctions/DriveOrderHttpTrigger.cs`:

```csharp
// Log incoming headers for debugging
LogHeaders(req);

// Validate authentication header
if (!_authService.ValidateHeader(req))
```

Every inbound header is logged — including the shared secret — and it happens **before** the auth
check, so unauthenticated callers can write to the log.

**Fix:** redact the auth header, and move the logging below the check.

## Medium — non-constant-time secret comparison

`DriveFunctions/Services/AuthService.cs` compares the shared secret with `==`. Comparison time
depends on the shared prefix.

```csharp
CryptographicOperations.FixedTimeEquals(
    Encoding.UTF8.GetBytes(supplied), Encoding.UTF8.GetBytes(expected));
```

Also fail closed when the configured value is blank — otherwise a missing setting accepts a missing
header.

## Medium — webhook payloads unauthenticated beyond the function key

`SmartCarWebhookTrigger` verifies nothing about the payload. It implements the vendor's
challenge/response for *registration* (`HandleVerifyEvent`, HMAC over the challenge), which is a
different thing from verifying that an incoming event was signed by the vendor.

**Fix:** if the vendor signs payloads, verify the HMAC over the **raw body** before deserializing,
with `FixedTimeEquals`.

## Low — telemetry drift

OpenTelemetry in Echoes, Autoplan API and OFV; `Microsoft.ApplicationInsights.WorkerService` in
Easypark, HubSpot and Drive. Both work. Batch the migration; do not raise it per repo.

## Low — no central package management

Autoplan API and OFV have no `Directory.Packages.props`, so versions live in `.csproj` files and
drift silently from the rest of the estate.

## Low — documentation sprawl

HubSpot has 18 `.md` files at repo root (38 across the repo), most of them point-in-time status
reports: `SQL_PARAMETER_MISMATCH_COMPLETE_FIX.md`, `SQL_PARAMETER_FIX.md`, `MAPPINGSERVICE_UPDATE.md`,
`FINAL_STATUS_REPORT.md`, `COMPLETION_SUMMARY.md`, `UPDATE_COMPLETION_VERIFICATION.md`, … Real
knowledge, unfindable — the SQL alignment lessons in there are among the most valuable in the
codebase. Note it already has a `DOCUMENTATION_INDEX.md`, which shows the problem was recognised.

**Fix:** one `DOCUMENTATION.md` per the Echoes standard; archive point-in-time reports.

## Low — missing pipeline or IaC

Autoplan API has neither, despite being a shared dependency of the other integrations. Confirm
deployment is not centralised elsewhere before reporting.
