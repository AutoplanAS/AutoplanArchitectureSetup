# API handler pattern

## Source patterns

- Auth handlers: `api/auth/login.js`, `api/auth/me.js`, `api/auth/register.js`
- Data handlers: `api/vehicles/index.js`, `api/vehicles/[id].js`
- Admin handlers: `api/admin/users.js`, `api/admin/companies.js`
- Host adapter: `server.js`

## Standard flow

1. Check method and fail fast with 405.
2. Resolve authenticated user (`requireAuth`) for protected routes.
3. Validate identifiers and payload body fields.
4. Execute repository or query operation.
5. Normalize response payload shape.
6. Return stable status code and JSON contract.

## Design constraints

- No hidden fallbacks that mask backend failures.
- No role checks only in UI.
- No direct SQL string concatenation from request input.

