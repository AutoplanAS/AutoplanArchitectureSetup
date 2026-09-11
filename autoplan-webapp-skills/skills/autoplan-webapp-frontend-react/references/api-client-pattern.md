# API client pattern

## Source pattern

- Shared API module: `src/apiClient.js`

## Baseline behavior

1. Resolve `API_BASE` from `REACT_APP_API_BASE_URL` and fall back to `/api`.
2. Centralize request logic (`method`, headers, token, JSON parsing).
3. Provide endpoint-specific methods that hide transport details from UI components.
4. Normalize or translate technical API errors into user-friendly frontend messages when needed.
5. Keep fallback behavior for compatibility endpoints in one place.

## Required checks when adding endpoints

- Method/URL matches backend route contract.
- Token header applied for protected endpoints.
- Non-OK responses throw typed or stable errors.
- Frontend caller receives consistent return shapes.

