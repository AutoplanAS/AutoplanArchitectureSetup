# Resilience configuration

`Microsoft.Extensions.Http.Resilience` on every outbound client. It wraps retry, circuit breaker,
attempt timeout and total timeout in one call.

## The house configuration

```csharp
.AddStandardResilienceHandler(ConfigureResilience);

static void ConfigureResilience(HttpStandardResilienceOptions o)
{
    o.AttemptTimeout.Timeout = TimeSpan.FromSeconds(30);
    o.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
    o.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(60);
}
```

From `EchoesIntegration/Program.cs`. Reuse these values unless the API demands otherwise.

## The constraints will fail your startup

The options are validated when the handler is constructed, which means **at host startup**, not at
first request. Two rules:

- `AttemptTimeout` < `TotalRequestTimeout`
- `CircuitBreaker.SamplingDuration` >= 2 × `AttemptTimeout`

The Echoes values sit exactly on the second boundary (30s / 60s). Raising `AttemptTimeout` without
raising `SamplingDuration` breaks the host.

## What each setting does

| Setting | Meaning | Tuning |
|---|---|---|
| `AttemptTimeout` | Ceiling for one attempt | Just above the API's p99 |
| `TotalRequestTimeout` | Ceiling across all retries | ~3 × attempt |
| `CircuitBreaker.SamplingDuration` | Failure-rate sampling window | >= 2 × attempt |
| `Retry` | Retries with exponential backoff + jitter | Default 3 is fine |

Defaults retry on 5xx, 408, 429 and `HttpRequestException`. They do **not** retry 4xx, which is
correct — a 400 will fail again.

## Interaction with the client timeout

```
HttpClient.Timeout (100s)          outer ceiling — must be the largest
  └─ TotalRequestTimeout (90s)     across all retry attempts
       └─ AttemptTimeout (30s)     per attempt
```

If `HttpClient.Timeout` is lower than `TotalRequestTimeout`, the client cancels mid-retry and you
get a `TaskCanceledException` instead of the resilience handler's own error.

## Handler ordering

```csharp
.AddHttpMessageHandler<AuthHandler>()          // outer
.AddStandardResilienceHandler(Configure);      // inner
```

Registration order is outermost first. Auth outside resilience means the auth handler sees one
logical request and its own 401 retry is separate from transient retries — which is what you want,
since a 401 is not transient and should not consume the retry budget.

## Non-retryable POSTs

The standard handler retries on the assumption that requests are idempotent. If the API has a
non-idempotent POST without an idempotency key, either use a separate client without retry, or
confirm duplicate submissions are harmless. Blind retry on "create payment" is a real hazard.

## Repos without resilience

Easypark, OFV and Autoplan API have no resilience handler — a transient network blip fails the
whole sync. Add it when touching those clients; it is a two-line change.

Do not hand-roll retry loops. HubSpot's custom `MaxRetries` / `InitialBackoffSeconds` predates the
library and should be migrated rather than copied.
