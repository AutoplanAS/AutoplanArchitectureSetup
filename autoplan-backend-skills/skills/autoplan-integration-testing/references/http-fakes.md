# HTTP fakes

Unit tests never make a network call. Every API client test substitutes the `HttpMessageHandler`
underneath `HttpClient`, which is the lowest seam that still exercises your client's real URL
building, header setting, serialisation and deserialisation.

**Do not fake your own `IEchoesApiClient` when testing the client itself** -- that tests the mock.
Fake your own interface only when testing a *consumer* of the client.

There are three fakes in the estate. They are not interchangeable.

## 1. Matcher-based -- `EchoesIntegration.Tests/Helpers/MockHttpMessageHandler.cs`

```csharp
public class MockHttpMessageHandler : HttpMessageHandler
{
    private readonly List<(Func<HttpRequestMessage, bool> Match,
                           Func<HttpRequestMessage, HttpResponseMessage> Respond)> _handlers = [];

    public List<HttpRequestMessage> Requests { get; } = [];
    public List<string?> RequestBodies { get; } = [];

    public void When(Func<HttpRequestMessage, bool> match, HttpStatusCode statusCode, string jsonBody)
        => _handlers.Add((match, _ => new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(jsonBody, Encoding.UTF8, "application/json"),
        }));

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        RequestBodies.Add(request.Content is null
            ? null : await request.Content.ReadAsStringAsync(cancellationToken));

        foreach (var (match, respond) in _handlers)
            if (match(request)) return respond(request);

        return new HttpResponseMessage(HttpStatusCode.NotFound)
        {
            Content = new StringContent("{}", Encoding.UTF8, "application/json"),
        };
    }
}
```

**Use when** the call order is an implementation detail, or one test drives several endpoints.
First registered match wins, so register the most specific first.

**The trap, documented in the source at lines 43-46:** an unmatched request returns **404**, not an
error. That is deliberate -- it makes a forgotten `When()` surface as a failed assertion rather than
a hang. But if you are testing "the API returned 200 with an empty body", you *must* register an
explicit `When(...)` returning 200. Otherwise the fallback 404 fires and your test exercises the
not-found path while appearing to test the empty-body path.

## 2. Sequence-based -- `EchoesAuthenticationTests.cs:205`

A private nested class, because it is only useful to one file:

```csharp
private sealed class SequenceHandler(params (HttpStatusCode Status, string Body)[] responses)
    : HttpMessageHandler
{
    private int _index;

    public List<HttpRequestMessage> Requests { get; } = [];
    public List<string?> RequestBodies { get; } = [];

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        RequestBodies.Add(request.Content is null
            ? null : await request.Content.ReadAsStringAsync(cancellationToken));

        var (status, body) = _index < responses.Length ? responses[_index] : responses[^1];
        _index++;

        return new HttpResponseMessage(status)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
    }
}
```

**Use when the order *is* the behaviour under test** -- 401 then 200, or page 1 then page 2 then an
empty page.

Note `responses[^1]`: once the list is exhausted the **last response repeats forever**. That is what
makes it safe for pagination-termination tests -- if your loop fails to stop, it keeps receiving the
empty page rather than throwing, and the test fails on a request-count assertion instead of an
`IndexOutOfRangeException`. The failure message then tells you what actually went wrong.

## 3. Queue-based -- `EasyparkIntegration.Tests/Helpers/MockHttpMessageHandler.cs`

```csharp
public class MockHttpMessageHandler : HttpMessageHandler
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly Queue<HttpResponseMessage> _responses = new();

    public List<HttpRequestMessage> SentRequests { get; } = [];

    public void EnqueueJsonResponse<T>(T content, HttpStatusCode statusCode = HttpStatusCode.OK)
    {
        var json = JsonSerializer.Serialize(content, JsonOptions);
        _responses.Enqueue(new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        });
    }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        SentRequests.Add(request);

        if (_responses.Count == 0)
            throw new InvalidOperationException($"No response queued for {request.Method} {request.RequestUri}");

        return Task.FromResult(_responses.Dequeue());
    }
}
```

**Use when** you want to enqueue typed objects rather than write JSON by hand -- `EnqueueJsonResponse`
serialises with `JsonSerializerDefaults.Web`, matching the client's own settings.

Two differences that matter:

- **It throws on exhaustion.** Louder than Echoes' 404, and better for catching an unexpected extra
  request. Worse for pagination-termination tests, where the exception masks the request count.
- **It does not record request bodies.** You cannot assert on what you POSTed. If you need that, add
  it or use one of the other two.

## Choosing

| Situation | Fake |
|---|---|
| Several endpoints, order irrelevant | matcher (1) |
| Auth renewal, retry, pagination | sequence (2) |
| Typed responses, order matters, want a loud failure | queue (3) |
| Need to assert on the request body | matcher (1) or sequence (2) |

## Wiring it up

```csharp
var handler = new SequenceHandler((HttpStatusCode.OK, """{"token":"newtoken"}"""));
var httpClient = new HttpClient(handler) { BaseAddress = new Uri("https://api.example.test/") };
var client = new EchoesAccountClient(
    httpClient, Options.Create(options), NullLogger<EchoesAccountClient>.Instance);
```

Use `https://api.example.test/` -- `.test` is reserved by RFC 6761 and can never resolve. Easypark
uses `https://test.api.com`, which is a **real registrable domain**; a request that escapes the fake
would leave the building. Prefer the reserved form.

To test a `DelegatingHandler` (auth, retry) rather than a client, set `InnerHandler`:

```csharp
var handler = new EchoesPrivacyKeyHandler(provider, NullLogger<EchoesPrivacyKeyHandler>.Instance)
{
    InnerHandler = inner,
};
return new HttpClient(handler) { BaseAddress = new Uri("https://api.example.test/") };
```

This is the only way to test the handler pipeline in isolation, and it is what makes the
401-renew-retry tests possible. See `EchoesAuthenticationTests.cs:195-202`.
