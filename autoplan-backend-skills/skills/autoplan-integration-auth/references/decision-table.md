# Decision table

Every authentication pattern in these integrations, and where it is implemented.

## Outbound — calling someone else's API

| Pattern | Used by | Credential | Renewal trigger | Implementation |
|---|---|---|---|---|
| OAuth2 client credentials (Entra ID) | Autoplan API | client id + secret + scope | expiry − 60s, or 401 | `AutoplanAPIIntegrations/Services/AutoplanTokenService.cs` |
| Dual token: API key mints privacy key | Echoes | account API key → privacy key | expiry − 7 days, or 401 | `EchoesIntegration/Api/EchoesPrivacyKeyProvider.cs` + `Http/EchoesPrivacyKeyHandler.cs` |
| Login endpoint returning a bearer token | Easypark | username + password | none (flaw — see below) | `EasyparkIntegration/Api/EasyparkApiClientBase.cs` |
| OAuth2 authorization code + refresh | SmartCar | per-user tokens in Table Storage | refresh token | `SmartCarIntegration/Services/SmartCarAuthService.cs` |
| Basic auth | OFV | username + password | none needed | `OFVIntegration/Services/OFVApiClient.cs` |
| Static private-app token | HubSpot | bearer token | none needed | `HubSpotDataRetriever` |
| OAuth2 client credentials → GraphQL | Drive (Wayke) | client id + secret | cached | `DriveFunctions/Services/WaykeGraphQLLookupClient.cs` |

## Inbound — protecting our functions

| Pattern | Used by | Mechanism |
|---|---|---|
| Function key | all repos | `AuthorizationLevel.Function` |
| Shared-secret header | Drive | `Auth__RequiredHeaderName` / `Auth__RequiredHeaderValue`, validated by `IAuthService` |
| HMAC signature | SmartCar webhook | signature verified against the payload before processing |

## Picking one

```
Does an external system call US?
├─ yes → inbound-auth.md
│         webhook from a vendor that signs?      → HMAC
│         partner posting to us?                 → shared-secret header + function key
│         internal/manual?                       → function key
│
└─ no, we call THEM → does the credential expire?
          ├─ no  → static key or basic auth on the typed client
          └─ yes → is it per-user?
                    ├─ yes → authorization-code-flow.md (token per user in storage)
                    └─ no  → is it minted by another credential?
                              ├─ yes → expiring-keys.md (two clients + handler)
                              └─ no  → oauth2-client-credentials.md (token service)
```

## Known flaws — do not copy

**Easypark: per-instance token cache, no refresh.**

```csharp
public abstract class EasyparkApiClientBase
{
    private string? _token;   // instance field

    protected async Task<string> EnsureTokenAsync(CancellationToken cancellationToken)
    {
        _token ??= await LoginAsync(cancellationToken);
        return _token;
    }
}
```

Two problems: each client instance logs in separately, and once cached the token is never
refreshed — expiry produces 401s forever. Replace with a singleton provider plus a
`DelegatingHandler` when touching this code.

**OFV: credentials committed to git.** `OFVIntegration/local.settings.json` is tracked and holds a
live username and password. See [secrets-management.md](secrets-management.md).

**OFV / HubSpot: no 401 handling.** A rotated or expired credential fails every call until the app
is redeployed.

## What good looks like

Autoplan API and Echoes both get it right, from different angles:

- **Autoplan API** — centralised singleton token service, `SemaphoreSlim`-guarded refresh, double-checked cache, 60s expiry buffer, explicit `InvalidateToken()` for callers that see a 401.
- **Echoes** — the same lifecycle behind a `DelegatingHandler`, so the 401 retry is automatic and callers never think about auth at all.

Echoes' approach is preferred for new work: the caller cannot forget to handle the 401.
