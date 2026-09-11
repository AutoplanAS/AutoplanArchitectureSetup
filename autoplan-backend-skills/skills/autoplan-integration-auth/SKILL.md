---
name: autoplan-integration-auth
description: "Wire authentication in an Autoplan integration — outbound OAuth2 client credentials, expiring API/privacy keys, authorization-code flows, and inbound function/header/HMAC auth. WHEN: \"authenticate against an API\", \"OAuth2 client credentials\", \"token service\", \"cache a token\", \"refresh token on 401\", \"getting 401 from the API\", \"DelegatingHandler auth\", \"API key header\", \"verify a webhook signature\", \"HMAC signature\", \"secure my function endpoint\", \"where do I put the client secret\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementations: AutoplanAPIIntegrations/Services/AutoplanTokenService.cs, EchoesIntegration/Http/EchoesPrivacyKeyHandler.cs
---

# Autoplan Integration Auth

Five authentication patterns already in production across these integrations. Pick by shape, not
by preference.

## Rules

1. ⛔ **No secrets in source or in tracked files.** `local.settings.json` is git-ignored; Azure app settings or Key Vault in the cloud; CI secret stores (Azure DevOps secret variables / variable groups or GitHub secrets) in delivery. This has already gone wrong once — see [secrets-management.md](references/secrets-management.md).
2. **Token caches are singletons.** A per-instance or per-scope cache mints a new token on every call.
3. **A 401 must invalidate the cache and retry exactly once.** Never retry more — a genuinely wrong credential would loop.
4. **Clone the request before retrying** when it may carry a body. An `HttpRequestMessage` and its content stream cannot reliably be sent twice.
5. **Guard the refresh with a `SemaphoreSlim`** and double-check the cache inside the lock.
6. **Never log a token, key, secret or signature.** Log that a renewal happened, not what it produced.

## Choosing the pattern

| The API gives you | Pattern | Reference |
|---|---|---|
| Client id + secret, an OAuth2 token endpoint | Client credentials + cached token service | [oauth2-client-credentials.md](references/oauth2-client-credentials.md) |
| A long-lived key that mints short-lived keys | Two clients + `DelegatingHandler` with renewal | [expiring-keys.md](references/expiring-keys.md) |
| A user-consent flow, per-user tokens | Authorization code + refresh token storage | [authorization-code-flow.md](references/authorization-code-flow.md) |
| A static API key | Header on the typed client | [oauth2-client-credentials.md](references/oauth2-client-credentials.md#static-api-keys) |
| Inbound calls to *our* functions | Function key, shared-secret header, or HMAC | [inbound-auth.md](references/inbound-auth.md) |

Full decision table with the repo each pattern comes from:
[decision-table.md](references/decision-table.md).

## The two mechanisms

Everything below is built from one of two things.

**A singleton token provider** owns the credential lifecycle — cache, expiry, refresh, invalidate:

```csharp
public interface I<Name>TokenService
{
    Task<string?> GetTokenAsync(CancellationToken cancellationToken);

    /// <summary>Invalidates the cached token so the next call forces a refresh.
    /// Call this when a downstream API returns 401.</summary>
    void InvalidateToken();
}
```

Registered `AddSingleton`. Always.

**A `DelegatingHandler`** applies the credential per request and reacts to 401, so an expired
credential is renewed without recreating the `HttpClient`:

```csharp
builder.Services.AddTransient<<Name>AuthHandler>();

builder.Services.AddHttpClient<I<Name>ApiClient, <Name>ApiClient>(Configure)
    .AddHttpMessageHandler<<Name>AuthHandler>()
    .AddStandardResilienceHandler(ConfigureResilience);
```

Handlers must be `Transient`. Registration order is outermost-first, so auth sits **outside**
resilience — a 401 retry is deliberate, not part of the transient retry budget.

## Expiry margins

Never treat a token as valid until the instant it expires; clock skew and in-flight requests will
bite you.

| Credential lifetime | Margin | Source |
|---|---|---|
| Minutes to hours (OAuth2 access token) | 60 seconds | `AutoplanTokenService.ExpiryBufferSeconds` |
| Days to a year (privacy key) | 7 days | `EchoesPrivacyKeyProvider.RenewalMargin` |

## Reference

- [Decision table](references/decision-table.md)
- [OAuth2 client credentials and static keys](references/oauth2-client-credentials.md)
- [Expiring keys and DelegatingHandler renewal](references/expiring-keys.md)
- [Authorization code flow](references/authorization-code-flow.md)
- [Inbound auth: function keys, headers, HMAC](references/inbound-auth.md)
- [Secrets management](references/secrets-management.md)

## Review checklist

- [ ] Token cache is a singleton
- [ ] Refresh guarded by `SemaphoreSlim` with a double-check inside the lock
- [ ] Expiry margin applied
- [ ] 401 invalidates and retries **once**
- [ ] Request cloned before the retry when a body may be present
- [ ] Non-standard scheme words set with `TryAddWithoutValidation`, after `Remove`
- [ ] No secret in any tracked file, including `.bicepparam`
- [ ] No token, key or signature written to logs
- [ ] Renewal path covered by a test
