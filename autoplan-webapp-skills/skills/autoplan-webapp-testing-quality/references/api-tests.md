# API test patterns

## Source patterns

- API tests: `tests/api/*.test.js`
- HTTP response mock helper: `tests/helpers/httpMocks.js`
- Module mocking loader: `tests/helpers/loadWithMocks.js`

## Recommended approach

1. Test handlers directly with mocked dependencies (`_db`, `_auth`, telemetry).
2. Assert response status and response shape.
3. Assert query parameters and branch behavior for admin vs non-admin paths.
4. Assert normalization behavior where API composes payload output.

## Typical test cases

- Login rejects non-POST.
- Login validates required fields.
- Vehicles list applies company filter for non-admin users.
- Auth failure prevents data query execution.

