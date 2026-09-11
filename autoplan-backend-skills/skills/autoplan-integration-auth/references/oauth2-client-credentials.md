# OAuth2 client credentials

For machine-to-machine APIs with a client id and secret. Reference:
`AutoplanAPIIntegrations/Services/AutoplanTokenService.cs`.

## The token service

```csharp
public interface IAutoplanTokenService
{
    /// <summary>
    /// Returns a valid access token, fetching a fresh one only when the
    /// cached token is absent or within 60 seconds of expiry.
    /// Returns null if the token endpoint is unreachable or credentials are wrong.
    /// </summary>
    Task<string?> GetTokenAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Invalidates the cached token so the next call to GetTokenAsync forces a refresh.
    /// Call this when a downstream API returns 401.
    /// </summary>
    void InvalidateToken();
}
```

Registered as a **singleton** so all scoped services share one cached token.

## Double-checked caching

```csharp
private const int ExpiryBufferSeconds = 60;

private readonly SemaphoreSlim _lock = new(1, 1);
private string? _cachedToken;
private DateTimeOffset _tokenExpiry = DateTimeOffset.MinValue;

public async Task<string?> GetTokenAsync(CancellationToken cancellationToken)
{
    // Fast path: return cached token without acquiring the lock
    if (_cachedToken is not null && DateTimeOffset.UtcNow < _tokenExpiry)
        return _cachedToken;

    await _lock.WaitAsync(cancellationToken);
    try
    {
        // Re-check inside the lock in case another thread just refreshed
        if (_cachedToken is not null && DateTimeOffset.UtcNow < _tokenExpiry)
            return _cachedToken;

        return await RefreshTokenAsync(cancellationToken);
    }
    finally
    {
        _lock.Release();
    }
}
```

The re-check inside the lock is not optional. Without it, every thread queued on the semaphore
performs its own token request the moment it acquires the lock — a thundering herd against the
token endpoint exactly when the token expires.

Use `SemaphoreSlim`, not `lock`. You cannot `await` inside a `lock`.

## Invalidation

```csharp
public void InvalidateToken()
{
    _lock.Wait();
    try
    {
        _cachedToken = null;
        _tokenExpiry = DateTimeOffset.MinValue;
    }
    finally
    {
        _lock.Release();
    }
}
```

## The refresh

```csharp
private async Task<string?> RefreshTokenAsync(CancellationToken cancellationToken)
{
    if (string.IsNullOrWhiteSpace(_tenantId) || string.IsNullOrWhiteSpace(_clientId) ||
        string.IsNullOrWhiteSpace(_clientSecret) || string.IsNullOrWhiteSpace(_scope))
    {
        _logger.LogWarning("Autoplan credentials (TenantId, ClientId, ClientSecret, Scope) are not fully configured.");
        return null;
    }

    var tokenEndpoint = $"https://login.microsoftonline.com/{_tenantId}/oauth2/v2.0/token";

    try
    {
        using var client = _httpClientFactory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Post, tokenEndpoint)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = _clientId,
                ["client_secret"] = _clientSecret,
                ["grant_type"] = "client_credentials",
                ["scope"] = _scope
            })
        };

        var response = await client.SendAsync(request, cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogWarning("Autoplan token endpoint returned {StatusCode}. Response: {ErrorBody}",
                response.StatusCode, errorBody);
            return null;
        }

        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        using var json = JsonDocument.Parse(body);
        var root = json.RootElement;

        if (!root.TryGetProperty("access_token", out var tokenElement))
        {
            _logger.LogWarning("Autoplan token response did not contain access_token.");
            return null;
        }

        var expiresIn = root.TryGetProperty("expires_in", out var expiresElement)
            ? expiresElement.GetInt32()
            : 3600;

        _cachedToken = tokenElement.GetString();
        _tokenExpiry = DateTimeOffset.UtcNow.AddSeconds(expiresIn - ExpiryBufferSeconds);

        _logger.LogDebug("Autoplan access token refreshed. Valid for ~{Seconds}s (expires at {Expiry:u}).",
            expiresIn - ExpiryBufferSeconds, _tokenExpiry);

        return _cachedToken;
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Failed to acquire Autoplan access token.");
        return null;
    }
}
```

Details that matter:

- **`FormUrlEncodedContent`** — the OAuth2 token endpoint takes form encoding, not JSON.
- **Config checked before the call.** Missing configuration produces a message naming the settings, not a 400 from the identity provider.
- **The error body is logged.** Entra ID returns an `AADSTS` code that says exactly what is wrong; without it you are guessing.
- **`expires_in` defaulted to 3600** when absent, minus the buffer.
- **Returns `null` rather than throwing** — the caller decides whether a missing token is fatal. Pair with an explicit null check at the call site.
- ⛔ **The token itself is never logged.** Only its lifetime.

## Using it, with 401 retry

```csharp
var token = await _tokenService.GetTokenAsync(ct);
if (token is null)
{
    return null;   // or throw — the caller decides
}

request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
var response = await _httpClient.SendAsync(request, ct);

if (response.StatusCode == HttpStatusCode.Unauthorized)
{
    _tokenService.InvalidateToken();
    // retry ONCE with a cloned request — see expiring-keys.md
}
```

Prefer moving this into a `DelegatingHandler` so callers cannot forget it.

## Static API keys

No expiry, no service — set the header when configuring the typed client:

```csharp
builder.Services.AddHttpClient<IFooClient, FooClient>((sp, client) =>
{
    var options = sp.GetRequiredService<IOptions<FooOptions>>().Value;
    client.BaseAddress = new Uri(options.BaseUrl.TrimEnd('/') + "/");
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);
})
.AddStandardResilienceHandler(ConfigureResilience);
```

For a **non-standard scheme word** (`Apikey <token>`), `AuthenticationHeaderValue` reformats the
value and causes a 401. Use:

```csharp
client.DefaultRequestHeaders.TryAddWithoutValidation("Authorization", options.ApiKeyHeaderValue);
```

Normalise the prefix on the options class — see the scaffold skill's configuration reference.

## Basic auth

```csharp
var credentials = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{options.Username}:{options.Password}"));
client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", credentials);
```

Only over HTTPS. The password is a secret like any other — see
[secrets-management.md](secrets-management.md).
