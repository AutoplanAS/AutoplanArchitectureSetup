# Typed clients and structure

## Registration

```csharp
builder.Services.AddHttpClient<I<Name>ApiClient, <Name>ApiClient>((sp, client) =>
{
    var options = sp.GetRequiredService<IOptions<<Name>Options>>().Value;
    client.BaseAddress = new Uri(options.BaseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(100);
})
.AddHttpMessageHandler<<Name>AuthHandler>()      // optional, see the auth skill
.AddStandardResilienceHandler(ConfigureResilience);
```

`client.Timeout` is the outer ceiling across all retries. It must exceed
`TotalRequestTimeout` in the resilience options or it will cancel a retry sequence that the
resilience handler still considers in flight. Echoes uses 100s client / 90s total.

## Two clients when there are two auth schemes

When an API uses different credentials for different endpoint groups, use **two typed clients**,
not one client with conditional headers. Echoes does this: `EchoesAccountClient` uses the account
API key (valid only for Global, Account and Privacy-key requests), `EchoesApiClient` uses a
privacy key for everything else.

The split makes the scope boundary a compile-time fact instead of a runtime 401. Document which
endpoints belong to which client on the interface.

## Anatomy of a method

```csharp
public async Task<EchoesVehicle?> GetVehicleByVinAsync(string vin, bool archived = false, CancellationToken ct = default)
{
    var url = $"{AccountBase}/assets/vins?vin={Uri.EscapeDataString(vin)}&archived={(archived ? "true" : "false")}";
    using var response = await httpClient.GetAsync(url, ct);

    if (response.StatusCode == HttpStatusCode.NotFound)
    {
        return null;
    }

    await EnsureSuccessAsync(response, $"get vehicle by VIN {vin}", ct);
    return await ReadVehicleOrNullAsync(response, ct);
}
```

Points worth copying:

- `using var response` — responses are disposable and hold the connection.
- `Uri.EscapeDataString` on **every** interpolated query value. A VIN is safe; a registration number or free-text filter is not.
- Expected "absent" status checked *before* `EnsureSuccessAsync`.
- The operation description passed to `EnsureSuccessAsync` is human-readable and includes the identifier — it ends up in the log and the exception message.

## Serialization

```csharp
private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
```

Static and readonly. `JsonSerializerOptions` is expensive to construct and caches internal
metadata; building one per call is a measurable allocation problem.

Use `PostAsJsonAsync(url, request, JsonOptions, ct)` and
`ReadFromJsonAsync<T>(JsonOptions, ct)` — but see [api-quirks.md](api-quirks.md) for why reads
often need `ReadOrDefaultAsync` instead.

## DTOs

DTOs live in `Models/`, mirror the API's JSON, and carry `[JsonPropertyName]`:

```csharp
public class EchoesPrivacyKey
{
    [JsonPropertyName("token")]
    public string Token { get; set; } = string.Empty;

    /// <summary>Expiry as unix epoch milliseconds.</summary>
    [JsonPropertyName("expiredAt")]
    public long? ExpiredAt { get; set; }
}
```

- Model what the API actually sends, including awkward types. `expiredAt` is epoch milliseconds, so it is a `long?` — convert at the boundary with `DateTimeOffset.FromUnixTimeMilliseconds`, do not pretend it is a `DateTime`.
- Nullable for anything the API may omit.
- Non-nullable strings default to `string.Empty`.
- Never reuse a DTO as a table entity. Storage shape and API shape change for different reasons.

## Repeated route segments

```csharp
private string AccountBase => $"api/accounts/{_options.AccountId}";
```

Keeps the account id out of every route and gives one place to change when the API version moves.

## Avoid the monolith

`OFVIntegration/Services/OFVApiClient.cs` is 456 lines covering every endpoint with no
abstraction. Once a client passes roughly 300 lines, split by resource group — as Echoes does with
`EchoesApiClient` and `EchoesAccountClient`.

## Shared base class

Worth it when several clients share auth or error handling. `EasyparkApiClientBase` provides token
caching, an abstract `SetAuthHeader`, and RFC 9457 error translation to its subclasses.

Be aware of its flaw: it caches the token in an instance field (`private string? _token`), so each
client instance fetches its own and none of them refresh on 401. Prefer a singleton token provider
(see the auth skill) and keep the base class for error handling only.
