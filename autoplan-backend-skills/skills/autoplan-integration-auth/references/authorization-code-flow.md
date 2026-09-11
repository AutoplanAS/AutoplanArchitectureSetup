# Authorization code flow

For APIs where an end user grants access and each user has their own token. Reference:
`SmartCarIntegration/Services/SmartCarAuthService.cs` (Drive Integration repo).

Distinguishing feature: the token is **per user**, so it cannot live in a process-wide singleton
cache. It goes in Table Storage.

## The three moving parts

1. A redirect to the vendor's consent page (done by the vendor's SDK or a plain URL).
2. An HTTP-triggered **callback** function that receives `?code=` and exchanges it.
3. A **refresh** path used before every API call.

`SmartCarAuthCallbackTrigger.cs` is (2). `ISmartCarAuthService` is (1) and (3):

```csharp
public interface ISmartCarAuthService
{
    Task<SmartCarTokenResponse> ExchangeAuthCodeAsync(string code, string userId);
    Task<string> GetAccessTokenAsync(string userId);
}
```

## Exchanging the code

```csharp
/// <summary>
/// Exchanges an authorization code from SmartCar Connect for an access token and refresh token.
/// Stores the tokens in table storage for later use.
/// </summary>
public async Task<SmartCarTokenResponse> ExchangeAuthCodeAsync(string code, string userId)
{
    var body = new FormUrlEncodedContent(new Dictionary<string, string>
    {
        ["grant_type"] = "authorization_code",
        ["code"] = code,
        ["redirect_uri"] = _redirectUri
    });

    var tokenResponse = await RequestTokenAsync(body);
    tokenResponse.UserId = userId;
    tokenResponse.Code = code;
    await _tableStorageService.StoreSmartCarTokenAsync(tokenResponse);

    _logger.LogInformation("Successfully exchanged auth code for access token for user {UserId}", userId);
    return tokenResponse;
}
```

`redirect_uri` must match the registered one **exactly**, including trailing slash and scheme.
Mismatch gives `invalid_grant`, which reads like a bad code.

Authorization codes are single-use and short-lived. A retry of the exchange will fail; do not put
the exchange behind a resilience retry policy.

## Refresh on read

```csharp
/// <summary>
/// Retrieves a valid access token. If the stored token is expired, it will be refreshed automatically.
/// </summary>
public async Task<string> GetAccessTokenAsync(string userId)
{
    var token = await _tableStorageService.LoadSmartCarTokenAsync(userId);
    if (token is null)
    {
        throw new InvalidOperationException(
            $"No SmartCar token found for user {userId}. Exchange an authorization code first.");
    }

    if (!token.IsExpired)
    {
        return token.AccessToken;
    }

    _logger.LogInformation("Access token expired for user {UserId}, refreshing...", userId);
    var refreshedToken = await RefreshTokenAsync(token.RefreshToken);
    refreshedToken.UserId = userId;
    await _tableStorageService.StoreSmartCarTokenAsync(refreshedToken);

    return refreshedToken.AccessToken;
}
```

⚠️ **The refreshed token must be stored.** Many providers rotate the refresh token on use, so
skipping the write invalidates the user's grant and forces them to reconnect.

Missing token throws rather than returning null: nothing downstream can proceed, and "the user has
never connected" is a distinct condition from "the call failed".

## Expiry on the model

```csharp
/// <summary>
/// UTC timestamp when this token was obtained. Set by the application, not by SmartCar.
/// </summary>
[JsonPropertyName("obtained_at")]
public DateTime ObtainedAt { get; set; } = DateTime.UtcNow;

[JsonIgnore]
public bool IsExpired => DateTime.UtcNow >= ObtainedAt.AddSeconds(ExpiresIn).AddMinutes(-5);
```

OAuth2 returns `expires_in` (a duration), not an absolute time, so the absolute time has to be
derived and persisted. `ObtainedAt` is set by us right after the response — hence `[JsonIgnore]` on
`IsExpired`, which is computed and must not round-trip.

The 5-minute margin is the per-user equivalent of the token service's 60 seconds; larger because a
storage read plus refresh is slower than a cache hit.

## The token request

```csharp
private async Task<SmartCarTokenResponse> RequestTokenAsync(HttpContent body)
{
    using var client = _httpClientFactory.CreateClient();
    using var request = new HttpRequestMessage(HttpMethod.Post, TokenEndpoint);

    var credentials = Convert.ToBase64String(
        Encoding.UTF8.GetBytes($"{_clientId}:{_clientSecret}"));
    request.Headers.Authorization = new AuthenticationHeaderValue("Basic", credentials);
    request.Content = body;

    using var response = await client.SendAsync(request);
    var responseBody = await response.Content.ReadAsStringAsync();

    if (!response.IsSuccessStatusCode)
    {
        _logger.LogError("SmartCar token request failed with {StatusCode}: {Body}",
            (int)response.StatusCode, responseBody);
        throw new HttpRequestException(
            $"SmartCar token request failed ({(int)response.StatusCode}): {responseBody}");
    }

    var tokenResponse = JsonSerializer.Deserialize<SmartCarTokenResponse>(responseBody)
        ?? throw new InvalidOperationException("Failed to deserialize SmartCar token response");

    tokenResponse.ObtainedAt = DateTime.UtcNow;
    return tokenResponse;
}
```

Client credentials go in the **`Basic` header**, not the form body — the OAuth2 spec's preferred
form and what SmartCar requires. Some providers want them in the body instead; check.

Both the authorization-code and refresh-token grants share this method. Only `grant_type` differs.

## Storage

One row per user in Table Storage. Partition by tenant/provider, row key the user id, so a lookup
is a point read.

⛔ The access token and refresh token are secrets at rest. If the storage account is shared with
less-sensitive data, keep tokens in their own table and review who has the connection string.

## Deviations to fix when touching this code

`SmartCarAuthService` reads configuration straight from the environment in its constructor:

```csharp
_clientId = Environment.GetEnvironmentVariable("SMARTCAR_CLIENT_ID") ?? string.Empty;
```

This bypasses the options pattern used everywhere else: no validation, no `IOptions<T>`, and empty
strings that surface as a 401 from the token endpoint instead of a startup error. Move to a
`SmartCarOptions` class bound in `Program.cs` with `ValidateOnStart`.

`GetAccessTokenAsync` also has no `CancellationToken`. Add one when you touch the signature.
