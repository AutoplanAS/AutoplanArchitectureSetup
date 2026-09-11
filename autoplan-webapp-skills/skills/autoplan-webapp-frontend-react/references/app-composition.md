# App composition patterns

## Source patterns

- Root orchestration: `src/App.js`
- Auth state and bootstrap: `src/AuthContext.js`
- Feature components: `src/components/*`

## Guidance

1. `App` should orchestrate page state and route-like flow, not own all feature implementation details.
2. Authentication concerns belong in `AuthContext`:
   - token storage key management
   - bootstrap via `getCurrentUser`
   - login/logout actions
3. Feature screens should receive minimal state and callbacks through props.
4. For large flows, split by domain:
   - auth/session
   - vehicle return/reception flows
   - admin management

## Anti-patterns to avoid

- Duplicating auth token parsing across components.
- Direct `fetch` usage in components when a shared API client exists.
- Mixing API response parsing and UI rendering logic in many files.

