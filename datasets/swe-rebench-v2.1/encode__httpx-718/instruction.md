Authentication flows should preserve history.
If the authentication flow makes more that one request, then any prior requests should be visible in `response.history`.

### Additional contract requirements

- The `httpx.auth` module exposes a public class `Auth` with a `__call__(self, request: Request) -> AuthFlow` method.
- The `httpx.auth` module exposes a public type alias `AuthFlow`, a generator that yields `Request` objects and receives `Response` objects.
