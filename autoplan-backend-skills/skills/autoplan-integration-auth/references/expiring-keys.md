# Expiring keys and DelegatingHandler renewal

For APIs where one long-lived credential mints a second, short-lived one. Reference:
`EchoesIntegration/Api/EchoesPrivacyKeyProvider.cs` and `Http/EchoesPrivacyKeyHandler.cs`.

## The shape

Echoes has two tokens with different scopes:

| Token | Header | Grants | Expires |
|---|---|---|---|
| Account API key | `Apikey <token>` | Global, Account and Privacy-key endpoints only | no |
| Privacy key | `Privacykey <token>` | everything else, per granted feature | yes |

So there are **two typed clients**, and the second one gets a handler:

```csharp
// Account client — long-lived API key in the default headers, no auth handler.
builder.Services.AddHttpClient<IEchoesAccountClient, EchoesAccountClient>(ConfigureAccountClient)
    .AddStandardResilienceHandler(ConfigureResilience);

// The provider depends on the account client, and must be a singleton:
// a scoped provider would create a new privacy key on every call.
builder.Services.AddSingleton<IEchoesPrivacyKeyProvider, EchoesPrivacyKeyProvider>();

builder.Services.AddTransient<EchoesPrivacyKeyHandler>();

builder.Services.AddHttpClient<IEchoesApiClient, EchoesApiClient>(ConfigureApiClient)
    .AddHttpMessageHandler<EchoesPrivacyKeyHandler>()
    .AddStandardResilienceHandler(ConfigureResilience);
```

The auth handler is added **before** the resilience handler, which makes it outermost: the 401
renew-and-retry is a separate decision from the transient-fault retry budget.

Do not let the client that mints the key go through the handler — it would recurse.

## The handler

```csharp
/// <summary>
/// Attaches the Echoes privacy key to every vehicle/report request.
///
/// The privacy key is resolved per request rather than baked into the HttpClient's default
/// headers, so an expired key can be renewed without recreating the client. On a 401 the cached
/// key is discarded and the request is retried once with a freshly created key.
/// </summary>
public class EchoesPrivacyKeyHandler(
    IEchoesPrivacyKeyProvider privacyKeyProvider,
    ILogger<EchoesPrivacyKeyHandler> logger) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        // The retry needs its own message: an HttpRequestMessage (and its content stream)
        // cannot reliably be sent twice, which would break POST/PUT calls such as vehicle creation.
        var retryRequest = await CloneAsync(request, cancellationToken);

        await SetAuthorizationAsync(request, cancellationToken);
        var response = await base.SendAsync(request, cancellationToken);

        if (response.StatusCode != HttpStatusCode.Unauthorized)
        {
            retryRequest.Dispose();
            return response;
        }

        logger.LogInformation("Echoes returned 401 — renewing the privacy key and retrying once.");
        response.Dispose();
        privacyKeyProvider.Invalidate();

        await SetAuthorizationAsync(retryRequest, cancellationToken);
        return await base.SendAsync(retryRequest, cancellationToken);
    }

    private async Task SetAuthorizationAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var header = await privacyKeyProvider.GetPrivacyKeyHeaderAsync(ct);

        // Echoes expects the scheme name to be part of the token ("Privacykey <token>"),
        // so the whole value is set without letting HttpClient parse it into scheme/parameter.
        request.Headers.Remove("Authorization");
        request.Headers.TryAddWithoutValidation("Authorization", header);
    }
}
```

Four things are load-bearing:

1. **The clone happens first**, before the original is sent. Afterwards the content stream may already be consumed.
2. **`retryRequest.Dispose()` on the success path.** The clone is unmanaged-ish resource; leaking it on every successful call is a slow leak.
3. **`response.Dispose()` before retrying.** Otherwise the 401 response's connection is held.
4. **Retry exactly once.** A permanently invalid credential must fail, not loop.

## Cloning a request

```csharp
/// <summary>Copies a request so it can be sent a second time after the key is renewed.</summary>
private static async Task<HttpRequestMessage> CloneAsync(HttpRequestMessage request, CancellationToken ct)
{
    var clone = new HttpRequestMessage(request.Method, request.RequestUri)
    {
        Version = request.Version,
        VersionPolicy = request.VersionPolicy,
    };

    foreach (var header in request.Headers)
    {
        clone.Headers.TryAddWithoutValidation(header.Key, header.Value);
    }

    foreach (var option in request.Options)
    {
        clone.Options.Set(new HttpRequestOptionsKey<object?>(option.Key), option.Value);
    }

    if (request.Content is not null)
    {
        var buffered = await request.Content.ReadAsByteArrayAsync(ct);
        var content = new ByteArrayContent(buffered);
        foreach (var header in request.Content.Headers)
        {
            content.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        clone.Content = content;
    }
    return clone;
}
```

Copy this as-is. Content headers live on `request.Content.Headers`, not `request.Headers` — miss
that and the retry loses its `Content-Type` and comes back 415. `Options` carry the resilience
pipeline's per-request state; dropping them changes retry behaviour on the second attempt.

## The provider

```csharp
public interface IEchoesPrivacyKeyProvider
{
    /// <summary>
    /// Returns the Authorization header value ("Privacykey &lt;token&gt;") to use for
    /// vehicle and report requests, creating or renewing the key when required.
    /// </summary>
    Task<string> GetPrivacyKeyHeaderAsync(CancellationToken ct = default);

    /// <summary>Discards the cached key so the next call creates a fresh one (used after a 401).</summary>
    void Invalidate();
}
```

Same double-checked `SemaphoreSlim` cache as the OAuth2 token service, with two differences.

**A 7-day renewal margin**, because the key lives for months:

```csharp
/// <summary>Renew this long before the key actually expires.</summary>
private static readonly TimeSpan RenewalMargin = TimeSpan.FromDays(7);

private bool TryGetCached(out string header)
{
    var cached = _cachedHeader;
    if (cached is not null && (_expiresAt is null || _expiresAt > DateTimeOffset.UtcNow.Add(RenewalMargin)))
    {
        header = cached;
        return true;
    }

    header = string.Empty;
    return false;
}
```

**A flag for the configured key.** A key supplied through configuration has no known expiry, so it
cannot be renewed pre-emptively — only a 401 reveals it is dead:

```csharp
// A configured key is used as-is: its expiry is unknown, so a 401 triggers
// Invalidate() and the key is then abandoned in favour of a freshly created one.
// Without that flag an expired configured key would be handed out forever.
var configured = _options.PrivacyKeyHeaderValue;
if (configured is not null && !_configuredKeyRejected)
{
    _cachedHeader = configured;
    _expiresAt = null;
    return configured;
}

var created = await accountClient.CreatePrivacyKeyAsync(
    _options.PrivacyKeyValidityDays, _options.PrivacyKeyFeatures, ct);
_cachedHeader = EchoesOptions.EnsurePrefix(created.Token, "Privacykey");
_expiresAt = created.ExpiredAt is > 0
    ? DateTimeOffset.FromUnixTimeMilliseconds(created.ExpiredAt.Value)
    : null;
```

```csharp
public void Invalidate()
{
    // The rejected key may be the configured one; mark it so the next resolution
    // creates a replacement instead of returning the same rejected value.
    if (_cachedHeader is not null && _cachedHeader == _options.PrivacyKeyHeaderValue)
    {
        _configuredKeyRejected = true;
    }

    _cachedHeader = null;
    _expiresAt = null;
}
```

Without `_configuredKeyRejected` the system deadlocks on itself: `Invalidate()` clears the cache,
the next resolution reads the same expired configured key, gets another 401, forever.

`_expiresAt is null` means "unknown expiry" and is treated as still valid — the 401 path is the
only signal.

The expiry arrives as **unix epoch milliseconds** (`expiredAt`), so it is a `long?` on the model
and converted with `DateTimeOffset.FromUnixTimeMilliseconds`.

## Logging

```csharp
logger.LogInformation(
    "Created Echoes privacy key with features {Features}, expiring {ExpiresAt}",
    string.Join(", ", created.Features), _expiresAt);
```

Features and expiry, never the token. Enough to answer "did it renew, and what can it do".

## Testing the renewal

With `MockHttpMessageHandler`, queue a 401 followed by a 200 for the same route and assert:

- the key provider was asked twice,
- the second request carried a different `Authorization` value,
- a POST's body survived the retry intact,
- a persistent 401 results in exactly two attempts, not a loop.

The body assertion is the one that catches a broken clone.
