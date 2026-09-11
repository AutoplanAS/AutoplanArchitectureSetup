# Inbound auth: protecting our functions

Three layers, used together, when something calls **us**.

## 1. Function-level authorization (always)

```csharp
[Function("DriveOrderHttpTrigger")]
public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
```

`AuthorizationLevel.Function` on every HTTP trigger. Every HTTP trigger across these repos uses it.

⛔ `AuthorizationLevel.Anonymous` needs an explicit justification in a code comment plus another
auth mechanism in the handler. There is no anonymous endpoint in these integrations today; keep it
that way.

Function keys are managed in Azure, rotatable without a deploy, and never appear in source.

## 2. Shared-secret header (partner-facing endpoints)

Reference: `DriveFunctions/Services/AuthService.cs`.

```csharp
public interface IAuthService
{
    bool ValidateHeader(HttpRequest req);
}

public class AuthService : IAuthService
{
    private readonly string _requiredHeaderName;
    private readonly string _requiredHeaderValue;

    public AuthService(IOptions<AuthOptions> options)
    {
        _requiredHeaderName = options.Value.RequiredHeaderName;
        _requiredHeaderValue = options.Value.RequiredHeaderValue;
    }

    public bool ValidateHeader(HttpRequest req)
    {
        return req.Headers.TryGetValue(_requiredHeaderName, out var values) &&
               values.FirstOrDefault() == _requiredHeaderValue;
    }
}
```

Both the header **name** and **value** come from configuration (`Auth__RequiredHeaderName`,
`Auth__RequiredHeaderValue`), so the partner can dictate the header name without a code change.

At the top of the trigger, before any work:

```csharp
// Validate authentication header
if (!_authService.ValidateHeader(req))
{
    _logger.LogWarning("Missing or invalid authentication header");
    return new UnauthorizedResult();
}
```

Rules:

- Auth check **first**, before parsing the body or touching storage.
- `UnauthorizedResult` (401), with no detail about what was wrong.
- Log the rejection, never the received or expected value.

⚠️ `DriveOrderHttpTrigger` calls `LogHeaders(req)` **before** the auth check, which writes every
inbound header — including the secret — to logs. Redact the auth header, or move the logging below
the check, when you next touch that file.

⚠️ `values.FirstOrDefault() == _requiredHeaderValue` is an ordinal comparison whose duration depends
on the shared prefix. For a high-value secret over the public internet prefer a fixed-time compare:

```csharp
CryptographicOperations.FixedTimeEquals(
    Encoding.UTF8.GetBytes(supplied), Encoding.UTF8.GetBytes(expected));
```

Also guard against an empty configured value matching an empty header — fail closed if
`RequiredHeaderValue` is blank, and enforce that with `ValidateOnStart`.

## 3. Webhooks

### Challenge/response registration

SmartCar verifies that we own the application management token by posting a `VERIFY` event with a
challenge that we must HMAC back. Reference: `SmartCarService.HandleVerifyEvent`.

```csharp
public string HandleVerifyEvent(SmartCarWebhookEvent webhookEvent)
{
    var applicationManagementToken = Environment.GetEnvironmentVariable("SMARTCAR_APPLICATION_MANAGEMENT_TOKEN")
        ?? throw new InvalidOperationException("SMARTCAR_APPLICATION_MANAGEMENT_TOKEN is not configured");
    var challenge = webhookEvent.Data?.Challenge
        ?? throw new InvalidOperationException("VERIFY event missing challenge data");

    using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(applicationManagementToken));
    var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(challenge));
    return Convert.ToHexString(hash).ToLowerInvariant();
}
```

Handled before the normal event routing:

```csharp
if (string.Equals(webhookEvent.EventType, VerifyEventType, StringComparison.OrdinalIgnoreCase))
{
    var hmac = _smartCarService.HandleVerifyEvent(webhookEvent);
    return new OkObjectResult(new { challenge = hmac });
}
```

Hex encoding, lower case, and `HMACSHA256` are all dictated by the vendor. Confirm each against
their docs; the wrong encoding fails registration with no useful error.

`using var hmac` matters — `HMACSHA256` holds unmanaged state.

### Verifying that a payload really came from the vendor

⚠️ **Not implemented today.** `SmartCarWebhookTrigger` relies solely on the function key. That is a
real but limited protection: anyone holding the key can post any payload.

For a new webhook, if the vendor signs its payloads, verify the signature:

1. Read the raw body **as a string first** — the signature covers exact bytes, so verify before deserializing.
2. Recompute the HMAC over the raw body with the shared secret.
3. Compare with `CryptographicOperations.FixedTimeEquals`.
4. Reject with 401 and log the event id only.
5. Only then parse.

`SmartCarWebhookTrigger` already reads the body as a string before parsing, so the hook point
exists.

### Webhook handler shape (worth copying)

`SmartCarWebhookTrigger` gets the response semantics right:

- Unreadable or empty body → `400`, no retry from the vendor.
- Unknown `eventType` → `400` naming the type.
- Known-but-not-actionable event (`VEHICLE_ERROR`) → **`200`** plus a warning log. Returning an error would make the vendor retry an event that will never succeed.
- Processing failure → `500`, so the vendor retries.

Choosing 200 vs 500 for each case is the whole design. 500 means "try again"; use it only when a
retry could work.

### Idempotency

Vendors retry, so the same event id will arrive twice. Key stored rows by the vendor's event id
(`SmartCarEventEntity`) so a replay overwrites rather than duplicates.

## Checklist for a new inbound endpoint

- [ ] `AuthorizationLevel.Function`
- [ ] Auth validated before any parsing or I/O
- [ ] 401 with no detail leaked
- [ ] No secret or full header dump in logs
- [ ] Fixed-time comparison for shared secrets
- [ ] Fails closed when the expected secret is unconfigured
- [ ] Webhook signature verified over the raw body, when the vendor provides one
- [ ] 200 vs 500 chosen deliberately per failure mode
- [ ] Idempotent on the vendor's event id
