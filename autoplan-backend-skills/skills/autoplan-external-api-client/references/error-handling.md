# Error handling

Two proven approaches. Use the simple one by default; use problem-details parsing when the API
returns RFC 9457 bodies.

## Baseline: typed exception with status and body

From `EchoesIntegration/Api/EchoesApiClient.cs`:

```csharp
private async Task EnsureSuccessAsync(HttpResponseMessage response, string operation, CancellationToken ct)
{
    if (response.IsSuccessStatusCode)
    {
        return;
    }

    var body = await response.Content.ReadAsStringAsync(ct);
    logger.LogError("<Name> API call failed ({Operation}): {StatusCode} {Body}", operation, (int)response.StatusCode, body);
    throw new <Name>ApiException(response.StatusCode, $"{operation} failed: {body}");
}
```

**The response body must be in both the log and the exception message.** A bare
`response.EnsureSuccessStatusCode()` throws "Response status code does not indicate success: 400
(Bad Request)" and discards the part that tells you why. Every hour lost to a vague 400 is an hour
this five-line method would have saved.

The exception type:

```csharp
public class <Name>ApiException(HttpStatusCode statusCode, string message) : Exception(message)
{
    public HttpStatusCode StatusCode { get; } = statusCode;
}
```

Keeping `StatusCode` lets callers branch — see the fallback pattern below.

## RFC 9457 problem details

When the API returns `application/problem+json`, parse it. From
`EasyparkIntegration/Api/EasyparkApiClientBase.cs`:

```csharp
private static void ThrowForError(HttpResponseMessage response, string context, string body, ILogger logger)
{
    EasyparkProblemDetail? problem = null;
    if (!string.IsNullOrWhiteSpace(body))
    {
        try { problem = JsonSerializer.Deserialize<EasyparkProblemDetail>(body, JsonOptions); }
        catch (JsonException) { /* body is not a problem-detail object — fall through to raw logging */ }
    }

    if (problem is not null)
    {
        logger.LogError(
            "Easypark API error [{context}] — status {status}, title: {title}, detail: {detail}, instance: {instance}, traceId: {traceId}",
            context, problem.Status ?? (int)response.StatusCode, problem.Title ?? response.ReasonPhrase,
            problem.Detail, problem.Instance, problem.TraceId);

        throw new HttpRequestException(
            $"Easypark API error [{context}]: {problem.Status ?? (int)response.StatusCode} {problem.Title} — {problem.Detail} (traceId: {problem.TraceId}, instance: {problem.Instance})");
    }

    logger.LogError("Easypark API error [{context}] — status {statusCode}. Body: {body}", context, (int)response.StatusCode, body);
    throw new HttpRequestException($"Easypark API error [{context}]: {(int)response.StatusCode} ({response.StatusCode}). Body: {body}");
}
```

```csharp
private sealed class EasyparkProblemDetail
{
    public string? Type { get; set; }
    public string? Title { get; set; }
    public int? Status { get; set; }
    public string? Detail { get; set; }
    public string? Instance { get; set; }
    public long? Timestamp { get; set; }
    public string? TraceId { get; set; }
}
```

Two things make this work:

- The parse is wrapped in `try/catch (JsonException)` with a **fallback to raw logging**. Error bodies are exactly where APIs stop honouring their own content type — an HTML error page from a gateway must not turn a 502 into a `JsonException`.
- `traceId` is captured. It is what the upstream vendor asks for when you report the problem.

Prefer a typed `<Name>ApiException` over `HttpRequestException` in new code so callers can inspect
the status.

## Two body-read overloads

Reading the content stream twice returns empty the second time. When the caller has already read
the body, pass it in:

```csharp
protected async Task EnsureSuccessAsync(HttpResponseMessage response, string context, CancellationToken ct);
protected void EnsureSuccessWithBody(HttpResponseMessage response, string context, string body);
```

## Expected failures are control flow, not errors

Some non-success responses are normal. `OdometerRetrievalService` in Echoes handles an odometer
report that isn't enabled on every account — Echoes answers `400 "Not yet available"` — by
catching it and falling back to the vehicle list, which also carries odometer values:

```csharp
/// <summary>
/// Generate the odometer report, optionally limited to specific asset ids.
/// Not enabled on every account: Echoes may answer 400 "Not yet available", so callers should
/// handle that and fall back to <see cref="ListVehiclesAsync"/>.
/// </summary>
```

Document the fallback on the interface. A caller cannot guess it.

## Per-item isolation in batches

In a loop over many items, one failure must not abort the run:

```csharp
foreach (var item in items)
{
    try
    {
        await ProcessAsync(item, ct);
        succeeded++;
    }
    catch (<Name>ApiException ex)
    {
        logger.LogError(ex, "Failed to process {Id}; continuing.", item.Id);
        failed++;
    }
}

logger.LogInformation("Processed {Succeeded} items, {Failed} failed.", succeeded, failed);
```

Catch the specific exception, not `Exception` — a `TaskCanceledException` from a shutdown should
end the loop, not be swallowed as an item failure.

## Logging

Structured, named placeholders, never interpolation:

```csharp
logger.LogError("<Name> API call failed ({Operation}): {StatusCode} {Body}", operation, (int)response.StatusCode, body);  // yes
logger.LogError($"<Name> API call failed: {response.StatusCode}");                                                        // no
```

Interpolation destroys queryability in Application Insights — every message becomes a distinct
string and you cannot aggregate by status code.

⛔ Never log tokens, keys, passwords or connection strings. When logging a request that carries
auth, log the URL and status, not the headers.
