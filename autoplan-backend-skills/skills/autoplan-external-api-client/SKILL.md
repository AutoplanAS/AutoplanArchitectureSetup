---
name: autoplan-external-api-client
description: "Build or review the typed HTTP client that calls a third-party API in an Autoplan integration — resilience, pagination, error translation and the API quirks our code works around. WHEN: \"call an external API\", \"write an API client\", \"typed HttpClient\", \"add an endpoint to the client\", \"handle pagination\", \"retry a failing API call\", \"JsonException on a successful response\", \"API returns 200 but empty\", \"my HttpClient URL is wrong\", \"problem details\", \"RFC 9457\", \"review this API client\"."
license: MIT
metadata:
  author: Autoplan Development
  version: "1.0.0"
  reference-implementation: EchoesIntegration/Api/EchoesApiClient.cs
---

# Autoplan External API Client

How we call third-party APIs. Reference implementations: `EchoesIntegration/Api/EchoesApiClient.cs`
(structure, pagination, quirk handling) and
`EasyparkIntegration/Api/EasyparkApiClientBase.cs` (RFC 9457 error translation).

Authentication is a separate concern — see the **`autoplan-integration-auth`** skill.

## Rules

1. **Typed clients only.** Registered with `AddHttpClient<IFooClient, FooClient>`. Never `new HttpClient()`, never inject `IHttpClientFactory` into domain services.
2. **`Api/` owns HTTP; `Services/` owns meaning.** A service that constructs a URL or reads a status code is in the wrong layer.
3. **One method per endpoint**, named for the operation, not the verb+route.
4. **Always `AddStandardResilienceHandler`.**
5. **`CancellationToken ct = default` on every async method**, passed to every await.
6. **Never let a raw `HttpRequestException` escape** — translate to a typed `<Name>ApiException` carrying status and body.
7. **Document quirks in XML comments on the interface.** The quirk is the API's, but the surprise is the caller's.

## Shape

```csharp
public interface I<Name>ApiClient
{
    /// <summary>
    /// Look up a thing by id. Returns null when not found.
    /// Note that <Name> signals "unknown id" with 200 and an <i>empty body</i>, not 404.
    /// </summary>
    Task<Thing?> GetThingAsync(string id, CancellationToken ct = default);
}

public class <Name>ApiClient(
    HttpClient httpClient,
    IOptions<<Name>Options> options,
    ILogger<<Name>ApiClient> logger) : I<Name>ApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly <Name>Options _options = options.Value;

    private string AccountBase => $"api/accounts/{_options.AccountId}";
}
```

Primary constructors, a `static readonly JsonSerializerOptions` (never construct per call), and a
computed base path for repeated route segments.

`JsonSerializerDefaults.Web` gives camelCase and case-insensitive matching, which is what these
APIs use. Keep `[JsonPropertyName]` on DTOs for anything that isn't a straight camelCase match.

## Routes are relative and must not start with `/`

`BaseAddress` ends in `/` (set in `Program.cs`). A relative URI beginning with `/` resets to the
host root and silently drops the base path.

```csharp
await httpClient.GetAsync($"{AccountBase}/assets/{id}", ct);   // correct
await httpClient.GetAsync($"/{AccountBase}/assets/{id}", ct);  // drops the base path
```

## Return null or throw?

| Situation | Behaviour |
|---|---|
| Resource genuinely absent (404, or 200 + empty body) | return `null` |
| Anything else non-success | throw `<Name>ApiException` |
| Success but empty body where a body is required | throw — the API broke its contract |

Echoes' `CreateVehicleAsync` throws on an empty body because a create must return the created
entity, while `GetVehicleByVinAsync` returns `null`. Same client, different contracts.

Do **not** return `null` for every failure. OFV's client does, and the caller cannot distinguish
"no such vehicle" from "the API is down" — every failure becomes a 404.

## Reference

- [Typed clients and structure](references/typed-clients.md)
- [Resilience configuration](references/resilience.md)
- [Error handling and RFC 9457](references/error-handling.md)
- [Pagination](references/pagination.md)
- [API quirks we work around](references/api-quirks.md)

## Review checklist

- [ ] No bare `HttpClient`; `Services/` makes no HTTP calls
- [ ] `AddStandardResilienceHandler` with valid timings
- [ ] Relative routes without a leading slash
- [ ] Empty-body responses handled via `ReadOrDefaultAsync`
- [ ] Pagination exits on a short page **and** has a max-page guard that logs when hit
- [ ] Non-success translated into a typed exception including the response body
- [ ] `CancellationToken` on every method and threaded through
- [ ] `static readonly JsonSerializerOptions`
- [ ] Quirks documented in XML comments
- [ ] Tested with `MockHttpMessageHandler`, no live calls
