# API quirks we work around

Real behaviours of the APIs these integrations talk to. Each cost debugging time once. Check for
them when onboarding a new API — they are common, not exotic.

## "Not found" as 200 with an empty body

Echoes answers an unknown VIN with `200` and **no body**. `ReadFromJsonAsync` throws
`JsonException` on an empty stream, so a normal not-found looks like a serialization bug.

```csharp
/// <summary>
/// Deserializes a response body, treating an empty body as the default value.
/// <Name> returns 200 with no content for some "not found" cases, which would otherwise
/// make <c>ReadFromJsonAsync</c> throw a <see cref="JsonException"/>.
/// </summary>
private static async Task<T?> ReadOrDefaultAsync<T>(HttpResponseMessage response, CancellationToken ct)
{
    var body = await response.Content.ReadAsStringAsync(ct);
    return string.IsNullOrWhiteSpace(body)
        ? default
        : JsonSerializer.Deserialize<T>(body, JsonOptions);
}
```

Use `ReadOrDefaultAsync` for every GET that can return "nothing". Keep `ReadFromJsonAsync` only
where an empty body is a genuine contract violation (e.g. the response to a create).

## The same API disagrees with itself about "not found"

In Echoes, an unknown **VIN** gives `200` + empty body, but an unknown **asset id** gives
`400 "Unknown vehicle"`:

```csharp
/// <summary>
/// Retrieve a vehicle by its Echoes asset id. Returns null when not found.
/// Unlike the VIN lookup, an unknown asset id yields 400 ("Unknown vehicle"), which surfaces
/// as <see cref="EchoesApiException"/> rather than null.
/// </summary>
```

Never assume consistency across endpoints of one API. Verify per endpoint and document the
difference on the interface.

## Non-standard `Authorization` scheme words

Echoes wants `Apikey <token>` and `Privacykey <token>`. `AuthenticationHeaderValue` parses and
re-emits the value, breaking it. Set it raw:

```csharp
// TryAddWithoutValidation, because Echoes expects the scheme word as part of the value
// ("Apikey <token>"); the typed AuthenticationHeaderValue would reformat it and cause a 401.
client.DefaultRequestHeaders.TryAddWithoutValidation("Authorization", options.ApiKeyHeaderValue);
```

Per request, `Remove("Authorization")` before adding — `TryAddWithoutValidation` appends, and two
`Authorization` headers is also a 401.

Normalise the prefix on the options class so a token pasted with or without it works (see the
scaffold skill's configuration reference).

## Two tokens with different scopes

Echoes' account API key is only valid for Global, Account and Privacy-key requests; everything
else needs a privacy key that expires. A single-credential assumption produces 401s that look
random.

Model as two typed clients. See the **`autoplan-integration-auth`** skill.

## Endpoints that aren't enabled on every account

The Echoes odometer report answers `400 "Not yet available"` on accounts without the feature —
a permanent 400 that means "use the other endpoint", not "your request was malformed".

Catch it and fall back. `ListVehiclesAsync` carries the latest odometer value per vehicle, so it
doubles as the fallback source.

## Repeated query parameters, singular name

```
assetId=1&assetId=2      correct
assetIds=1,2             rejected
```

Repeated-vs-comma-separated and singular-vs-plural are independent guesses, each 50/50. Check
both, then leave a comment.

## Epoch milliseconds

```csharp
/// <summary>Expiry as unix epoch milliseconds.</summary>
[JsonPropertyName("expiredAt")]
public long? ExpiredAt { get; set; }
```

Model as `long?` and convert at the boundary with `DateTimeOffset.FromUnixTimeMilliseconds`.
Letting `System.Text.Json` coerce it into a `DateTime` gives a date in 1970.

Watch for seconds vs milliseconds. A timestamp around 1.7×10⁹ is seconds; 1.7×10¹² is
milliseconds.

## Trailing slash on `BaseAddress`

```csharp
// The trailing slash matters: without it the last path segment of BaseAddress is dropped
// when combined with a relative request URI.
client.BaseAddress = new Uri(options.BaseUrl.TrimEnd('/') + "/");
```

And relative routes must not start with `/`, which resets to the host root.

## Ids that must exist on the account

Echoes' `DefaultVehicleTypeId` must match a type defined on the account; the default `0` makes
every creation fail with an unhelpful error.

```csharp
/// <summary>
/// Vehicle type id used when creating (activating) vehicles. Must exist on the account —
/// GET /api/diagnostics/vehicle-types lists the valid ids and validates this setting.
/// A wrong value (such as the default 0) makes every vehicle creation fail.
/// </summary>
```

For any config value that must match server-side data, add a diagnostics endpoint that lists the
valid values. Cheap to write, and it turns a support ticket into a self-service check.

## Recording a new quirk

When you find one:

1. Fix it where the code meets the API — in `Api/`, not in a caller.
2. Comment the workaround with **why**, so nobody "cleans it up".
3. Put it on the interface's XML doc if it changes the contract (returns null, may throw, needs a fallback).
4. Add a test that pins the behaviour — Echoes has `EchoesApiClientTests` covering the empty-body case.
5. Add it here.

`MockHttpMessageHandler` returns 404 for unmatched requests, so testing the "200 with empty body"
path needs an explicit `When(...)` returning 200 — otherwise the test silently exercises the 404
branch and proves nothing.
