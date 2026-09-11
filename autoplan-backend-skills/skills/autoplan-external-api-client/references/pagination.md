# Pagination

Three styles appear across these integrations. Identify which one the API uses before writing the
loop.

## 1. Offset / limit (Echoes)

```csharp
public async Task<IReadOnlyList<EchoesVehicle>> ListVehiclesAsync(IReadOnlyCollection<long>? assetIds = null, CancellationToken ct = default)
{
    // Echoes caps the page size at 100 and requires offset/limit paging beyond that.
    const int pageSize = 100;
    const int maxPages = 100;

    var assetFilter = assetIds is { Count: > 0 } ? "&" + BuildAssetIdQuery(assetIds) : string.Empty;
    var vehicles = new List<EchoesVehicle>();

    for (var page = 0; page < maxPages; page++)
    {
        var url = $"{AccountBase}/assets?offset={page * pageSize}&limit={pageSize}{assetFilter}";
        using var response = await httpClient.GetAsync(url, ct);
        await EnsureSuccessAsync(response, "list vehicles", ct);

        var batch = await ReadOrDefaultAsync<List<EchoesVehicle>>(response, ct) ?? [];
        vehicles.AddRange(batch);

        if (batch.Count < pageSize)
        {
            return vehicles;
        }
    }

    logger.LogWarning("Vehicle listing stopped after {MaxPages} pages ({Count} vehicles); more may exist.", maxPages, vehicles.Count);
    return vehicles;
}
```

Everything in this method is load-bearing:

- **`maxPages` guard.** An API that ignores `offset` — or a full page that is genuinely the last page — turns a `while(true)` into an infinite loop hammering a vendor. Bound it.
- **`LogWarning` when the guard trips.** Silently truncating results is a data-loss bug that looks like a working sync. The log is how you find out.
- **Short page means last page.** Do not make an extra request to confirm; a short page is definitive for offset/limit APIs.
- **Empty body tolerated** via `ReadOrDefaultAsync ?? []`.

## 2. Cursor / continuation token

```csharp
string? cursor = null;
var results = new List<T>();

for (var page = 0; page < maxPages; page++)
{
    var url = cursor is null ? "things?limit=100" : $"things?limit=100&after={Uri.EscapeDataString(cursor)}";
    using var response = await httpClient.GetAsync(url, ct);
    await EnsureSuccessAsync(response, "list things", ct);

    var envelope = await ReadOrDefaultAsync<PagedResponse<T>>(response, ct);
    if (envelope is null) break;

    results.AddRange(envelope.Results);

    cursor = envelope.Paging?.Next?.After;
    if (string.IsNullOrEmpty(cursor)) return results;   // no cursor means done
}
```

Termination is the **absence of a next cursor**, not a short page — cursor APIs may legitimately
return fewer items than requested and still have more. HubSpot works this way.

Always URL-escape the cursor. They are opaque and often contain `=` and `+`.

## 3. Request handle / two-step (OFV)

Some APIs make you create a request, then fetch results against a handle:

```csharp
// Step 1 — create the request, get a handle
var created = await CreateVehicleRequestAsync(request, ct);

// Step 2 — page through results using the handle
for (int offset = 0; offset < totalExpected; offset += pageSize)
{
    var result = await GetVehicleRequestResultAsync(created.RequestHandle, count: pageSize, offset, ct);
    // process
}
```

Handles usually expire, so do not cache one across a long-running job. If the result set can be
large, the two calls may need different timeouts.

## Choosing the page size

Use the API's documented maximum unless there's a reason not to — fewer round trips. Echoes caps
at 100; the constant carries a comment saying so. Never hardcode a page size without a comment
explaining where the number came from.

## Do not auto-paginate lazily

Return a materialised `IReadOnlyList<T>`, not an `IAsyncEnumerable<T>` that pages behind the
caller's back. Callers in `Services/` need to know how much data they pulled, and a lazy sequence
makes the cost invisible and the `CancellationToken` semantics subtle.

## Filtering while paging

Echoes expects a repeated parameter, and names it `assetId`, not `assetIds`:

```csharp
/// <summary>
/// Builds the asset id filter. Echoes expects the parameter repeated once per id
/// ("assetId=1&amp;assetId=2") and names it <c>assetId</c> — not <c>assetIds</c>.
/// </summary>
private static string BuildAssetIdQuery(IReadOnlyCollection<long> assetIds)
    => string.Join("&", assetIds.Select(id => $"assetId={id}"));
```

Repeated-vs-comma-separated is one of the most common wrong guesses when writing a client. Check
it, then write the comment.

Watch the URL length. A few thousand ids will exceed limits — batch the filter itself.

## Testing

Both paths need coverage:

- **Termination.** One full page then a short page returns everything and stops.
- **Guard.** Enough full pages to trip `maxPages` returns the accumulated results and logs a warning rather than looping.

With `MockHttpMessageHandler`, match on the `offset`/`after` value so each page gets a distinct
response.
