# Configuration and options

One options class per configuration section, bound and validated in `Program.cs`.
Reference: `EchoesIntegration/Configuration/EchoesOptions.cs`.

## The options class

```csharp
namespace <Name>Integration.Configuration;

/// <summary>
/// Configuration for the <Name> API.
///
/// Bound from the "<Name>" section: local.settings.json when running locally (git-ignored),
/// app settings in Azure. Keys and connection strings must never be committed.
/// </summary>
public class <Name>Options
{
    public const string SectionName = "<Name>";

    /// <summary><Name> API base URL.</summary>
    public string BaseUrl { get; set; } = "https://api.example.com";

    /// <summary>Account-level API key. Treat as a secret.</summary>
    public string ApiKey { get; set; } = string.Empty;

    /// <summary>Azure Table name holding ...</summary>
    public string StateTableName { get; set; } = "<Name>State";
}
```

Rules:

- `const string SectionName` on the class — never a string literal at the call site.
- Non-nullable strings default to `string.Empty`, not `null`. Validation catches the empty value with a clear message; a null gives you a `NullReferenceException`.
- Real defaults (base URLs, table names, page sizes) belong here, **not** in `Program.cs`. Easypark hardcodes defaults in `Program.cs`, which makes them untestable and requires a recompile to change.
- Document every property with `///`. `GenerateDocumentationFile` is on, so these are build-validated. Say what breaks when the value is wrong — see `EchoesOptions.DefaultVehicleTypeId`.

## Computed properties for API quirks

Normalisation belongs on the options class, not scattered across clients. Echoes requires the
scheme word inside the header value (`Apikey <token>`) and tolerates configuration stored either
way:

```csharp
public string ApiKeyHeaderValue => EnsurePrefix(ApiKey, "Apikey");

public static string EnsurePrefix(string value, string prefix)
{
    var trimmed = value.Trim();
    return trimmed.StartsWith(prefix + " ", StringComparison.OrdinalIgnoreCase)
        ? trimmed
        : $"{prefix} {trimmed}";
}
```

This means someone pasting a token with or without the prefix gets a working app either way.

## Key naming

Hierarchical, section-prefixed:

| Context | Form | Example |
|---|---|---|
| Code / `local.settings.json` | `Section:Key` | `Echoes:ApiKey` |
| Azure app settings, pipeline vars | `Section__Key` | `Echoes__ApiKey` |

The double underscore is how the Azure Functions host maps flat environment variables into
hierarchical configuration. Both forms refer to the same setting.

## local.settings.json

**Git-ignored.** Commit `local.settings.example.json` alongside it with empty secret values:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "APPLICATIONINSIGHTS_CONNECTION_STRING": "",

    "<Name>:BaseUrl": "https://api.example.com",
    "<Name>:ApiKey": "",
    "<Name>:DataStorageConnection": "UseDevelopmentStorage=true"
  }
}
```

Leaving `APPLICATIONINSIGHTS_CONNECTION_STRING` empty is deliberate — the conditional exporter in
`Program.cs` then skips export and traces locally only.

`UseDevelopmentStorage=true` targets Azurite. Start it before `func start`.

## ⛔ Secrets

`local.settings.json` **must** be in `.gitignore` before the first commit.

This has already gone wrong: `OFVIntegration/local.settings.json` is tracked in git and contains a
live API username and password. Adding the ignore rule later does not untrack the file and does
not remove it from history.

If you find a committed secret:

1. Rotate the credential first. Assume it is compromised.
2. `git rm --cached <file>` and add the ignore rule.
3. Audit history: `git log --all --full-history -- <file>`.
4. Purge from history if the repo is shared externally.

In Azure: app settings for non-secrets, Key Vault references for secrets. In pipelines: secret
variables passed via `--parameters`, never written into `.bicepparam` files.

## Validation

Every setting whose absence breaks the app gets a `.Validate(...)` in `Program.cs`. Use the
config key as the message:

```csharp
.Validate(o => !string.IsNullOrWhiteSpace(o.ApiKey), "<Name>:ApiKey is not configured")
.Validate(o => o.AccountId > 0, "<Name>:AccountId is not configured")
.ValidateOnStart();
```

For a value needed before DI resolves (a storage connection string used to construct a client
directly), fail fast inline:

```csharp
var conn = builder.Configuration["<Name>:DataStorageConnection"]
    ?? throw new InvalidOperationException("<Name>:DataStorageConnection is not configured");
```
