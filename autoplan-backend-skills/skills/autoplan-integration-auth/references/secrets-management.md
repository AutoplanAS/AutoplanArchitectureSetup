# Secrets management

## Where secrets live

| Environment | Location | Notes |
|---|---|---|
| Local dev | `local.settings.json` | **git-ignored**, never committed |
| Azure | Function App application settings | set by pipeline or `provision.ps1`, not in the Bicep file |
| Azure (preferred) | Key Vault reference | `@Microsoft.KeyVault(SecretUri=...)` in an app setting |
| CI/CD | Pipeline secret variables or a variable group | never in `azure-pipelines.yml` |

Committed to the repo, always: `local.settings.example.json` with empty values, documenting which
settings exist.

## What must be in `.gitignore`

```gitignore
local.settings.json
appsettings.Development.json
*.user
*.publishsettings
*.pubxml
.env
*.bicepparam
```

`*.bicepparam` is on the list because parameter files attract connection strings. If you need a
committed one, commit `main.example.bicepparam` with placeholders.

⚠️ **`.gitignore` only helps for untracked files.** A file already tracked keeps being committed no
matter what you add. Check with:

```powershell
git ls-files | Select-String "local.settings.json"
```

Empty output is what you want.

## This has already happened here

`OFVIntegration/local.settings.json` is **tracked in git** and contains a live username and
password for `https://integrasjon-ofv.qanto.no`. Anyone with repo read access has those
credentials, and they are in every clone and in the full history.

Remediation, in order:

1. **Rotate the credential first.** Until it is rotated, nothing else matters — the value is already distributed.
2. `git rm --cached OFVIntegration/local.settings.json`
3. Add `local.settings.json` to `.gitignore`, commit both together.
4. Commit `local.settings.example.json` with the keys and empty values.
5. Decide on history: rewriting Azure Repos history breaks every clone and is usually not worth it *if* step 1 is done. Record the decision.
6. Check the pipeline for the same values, and other repos for the same mistake.

Do the same check in any repo you touch. It takes one command.

## Configuration keys, not values

Options classes name the settings; the values arrive from the environment:

```csharp
public class OfvOptions
{
    public const string SectionName = "OFV";

    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}
```

⛔ Never a default value for a secret. An empty string that fails at startup beats a working default
that ships to production.

Validate at startup so a missing secret is a boot failure, not a 401 hours later:

```csharp
builder.Services.AddOptions<OfvOptions>()
    .Bind(builder.Configuration.GetSection(OfvOptions.SectionName))
    .Validate(o => !string.IsNullOrWhiteSpace(o.Username), "OFV:Username must be configured.")
    .Validate(o => !string.IsNullOrWhiteSpace(o.Password), "OFV:Password must be configured.")
    .ValidateOnStart();
```

Note `local.settings.json` uses `OFV__Username` (double underscore) while `GetSection` and error
messages use `OFV:Username`. Both address the same setting.

## Logging

⛔ Never log: tokens, API keys, passwords, connection strings, signatures, full request headers,
full request bodies for authenticated calls.

✅ Do log: that a token was refreshed, its expiry, which credential *name* was missing, the status
code and correlating ids.

```csharp
// good
_logger.LogDebug("Autoplan access token refreshed. Valid for ~{Seconds}s (expires at {Expiry:u}).",
    expiresIn - ExpiryBufferSeconds, _tokenExpiry);

// bad
_logger.LogDebug("Token: {Token}", token);
```

Two traps in this codebase:

- Logging an **error body** from a token endpoint is fine and useful (it carries `AADSTS` codes) — but confirm the provider does not echo the credential back.
- `DriveOrderHttpTrigger.LogHeaders(req)` dumps every inbound header, including the shared secret, and runs *before* the auth check.

## Bicep and provisioning

Secrets are passed in as `@secure()` parameters, never literals:

```bicep
@secure()
param ofvPassword string
```

`@secure()` keeps the value out of deployment history and portal output. Supply it from a pipeline
secret variable or a Key Vault reference.

Key Vault reference in an app setting, so the value never enters the deployment at all:

```
@Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/<name>/)
```

Requires the Function App's managed identity to have **Key Vault Secrets User**.

## If a secret leaks

1. Rotate immediately. Everything else is secondary.
2. Check where else the value was used — pipelines, other repos, docs, tickets.
3. Remove it from the tracked file and add the ignore rule in the same commit.
4. Decide on history rewrite explicitly, and write the decision down.
5. Look for the same class of mistake in the other integrations.
