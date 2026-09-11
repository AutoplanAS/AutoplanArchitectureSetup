# Known issues and workarounds

Things that have cost real debugging time in these repos. Each has a fix that must be applied
proactively.

## 1. Functions Worker SDK restore fails on clean CI agents

**Symptom.** Local build fine, pipeline fails restoring packages for a project called something
like `<Name>Integration.WorkerExtensions` that does not exist in the repo.

**Cause.** The Functions Worker SDK generates a `WorkerExtensions` project at build time. Its
inner restore does not inherit the outer build's NuGet configuration, so on a clean agent with no
machine-level `nuget.org` source it has no source to restore from.
(Azure Functions dotnet-worker issue #1888.)

**Fix.** Commit a repo-root `NuGet.config` with an explicit, cleared source:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <!-- Explicit source so the Functions Worker SDK's generated WorkerExtensions
       inner-build restore always resolves packages on clean CI agents. -->
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
```

`<clear />` matters — it drops inherited sources that may not exist on the agent.

## 2. `DotNetCoreCLI@2` test task fails where `dotnet test` succeeds

**Symptom.** `dotnet test` passes locally and in a bash step, but the `DotNetCoreCLI@2` task fails
on Linux agents. Echoes hit this as a recurring pipeline failure
(commit `c45d955`, "Fix recurring pipeline test failure on Linux agents").

**Cause.** Same root cause as #1 — the task's restore does not propagate config to the generated
inner build.

**Fix.** Use a bash step:

```yaml
- bash: |
    dotnet test "$(testProjectPath)" \
      --configuration $(buildConfiguration) \
      --logger trx \
      --results-directory "$(Agent.TempDirectory)/TestResults"
  displayName: 'Test'

- task: PublishTestResults@2
  displayName: 'Publish test results'
  condition: succeededOrFailed()
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '$(Agent.TempDirectory)/TestResults/**/*.trx'
```

**Do not "fix" this by commenting out the test step.** Easypark's pipeline has `dotnet test`
commented out (lines 59–64) while `PublishTestResults@2` still runs — producing a green test step
that ran nothing. That is worse than no tests, because it looks like coverage.

## 3. `BaseAddress` silently drops a path segment

**Symptom.** Requests hit the wrong URL; a base path like `/v2` disappears.

**Cause.** `new Uri(baseAddress, relativeUri)` replaces the last segment unless the base ends in
`/`.

**Fix.** Always `client.BaseAddress = new Uri(options.BaseUrl.TrimEnd('/') + "/");` and make every
relative route **not** start with `/`. A leading slash on the relative URI resets to the host root.

## 4. Resilience handler throws at startup

**Symptom.** Host fails immediately with an options-validation error from
`AddStandardResilienceHandler`.

**Cause.** The handler validates its own timings. `AttemptTimeout` must be less than
`TotalRequestTimeout`, and `CircuitBreaker.SamplingDuration` must be at least twice
`AttemptTimeout`.

**Fix.** The known-good Echoes values:

```csharp
o.AttemptTimeout.Timeout = TimeSpan.FromSeconds(30);
o.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
o.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
```

Change one and re-check all three.

## 5. `Authorization` header reformatted into a 401

**Symptom.** A token that works in curl gives 401 from the app.

**Cause.** `AuthenticationHeaderValue` parses the value into scheme + parameter and re-emits it
normalised. APIs that expect a non-standard scheme word — Echoes uses `Apikey <token>` and
`Privacykey <token>` — reject the result.

**Fix.** Set it raw:

```csharp
client.DefaultRequestHeaders.TryAddWithoutValidation("Authorization", options.ApiKeyHeaderValue);
```

Per request, `Remove("Authorization")` first — `TryAddWithoutValidation` appends rather than
replaces, and two `Authorization` headers is also a 401.

## 6. "Not found" returned as 200 with an empty body

**Symptom.** `JsonException` on a successful response.

**Cause.** Some APIs signal "unknown id" with `200` and no body. `ReadFromJsonAsync` throws on an
empty stream. Echoes does this for unknown VINs.

**Fix.** Read as string, treat empty as `default`:

```csharp
private static async Task<T?> ReadOrDefaultAsync<T>(HttpResponseMessage response, CancellationToken ct)
{
    var body = await response.Content.ReadAsStringAsync(ct);
    return string.IsNullOrWhiteSpace(body) ? default : JsonSerializer.Deserialize<T>(body, JsonOptions);
}
```

More in the **`autoplan-external-api-client`** skill.

## 7. Test project compiled into the function app

**Symptom.** Test assemblies or xUnit packages end up in the published output.

**Cause.** The test project lives inside the function project's folder, so the SDK's default
globbing picks it up.

**Fix.** Exclude it explicitly in the `.csproj`:

```xml
<ItemGroup>
  <Compile Remove="<Name>Integration.Tests/**" />
  <Content Remove="<Name>Integration.Tests/**" />
  <None Remove="<Name>Integration.Tests/**" />
</ItemGroup>
```

## 8. `local.settings.json` published to Azure

**Symptom.** Local settings override Azure app settings after deployment.

**Fix.** In the `.csproj`:

```xml
<None Update="local.settings.json">
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  <CopyToPublishDirectory>Never</CopyToPublishDirectory>
</None>
```
