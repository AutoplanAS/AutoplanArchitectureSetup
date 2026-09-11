# JWT and RBAC pattern

## Source patterns

- JWT helpers: `api/_auth.js`
- Login endpoint: `api/auth/login.js`
- Session bootstrap in client: `src/AuthContext.js`

## Contract

JWT should carry only claims the API actually uses for authorization and identity:

- `userId`
- `role`
- `companyId`
- identity display fields (`email`, `fullName`, optional `companyName`)

## RBAC checks

1. Role checks are enforced in backend handlers.
2. Company scope checks are enforced in backend repository access.
3. Frontend `isAdmin` is UX-only and never trusted for data protection.

