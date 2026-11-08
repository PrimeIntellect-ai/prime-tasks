impersonate call in v2 doesn't seem to work
I tried to call the impersonate call in the v2 branch and I always get a 401.  Looking at the code and at the documentation, it looks like it is missing the Bearer header.

### Additional contract requirements

- `UsersManager` (module `src/auth/UsersManager.js`) exposes a public method `impersonate(userId, settings, cb)`.
- `impersonate` throws an `ArgumentError` synchronously when `userId` is missing or invalid, when the settings object is missing, or when `settings.impersonator_id` or `settings.protocol` is missing or invalid. `userId` must be a string and not null or undefined; `settings` must be a non-null object; and `settings.impersonator_id` and `settings.protocol` must be strings.
- `settings.token` is required and must be a non-empty string. If it is missing or invalid, an `ArgumentError` is thrown synchronously.
- `settings.clientId` is an optional client identifier. The request body's `client_id` is `settings.clientId` when provided, otherwise the client ID configured on the manager.
- The impersonation HTTP request includes an `Authorization: Bearer <token>` header, where `<token>` is `settings.token`.
- When `cb` is omitted, `impersonate` returns a Promise that resolves with the impersonation response; when `cb` is supplied, it returns `undefined`.


- When `settings.token` is missing or empty, synchronously throw an `ArgumentError` with the exact message `token field is required`.
