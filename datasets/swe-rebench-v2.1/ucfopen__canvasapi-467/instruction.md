Handle Rate Limit
When a developer gets a little overzealous and implements multiprocessing, or has many applications/instances of an application using the same access token, It's possible to hit a rate limit. When that happens, Canvas returns a 403 status code. It appears that the only way to distinguish between being rate limited and another type of 403 is the response content will be `403 Forbidden (Rate Limit Exceeded)`.

A new exception (`RateLimitExceeded`?) would help distinguish between when the developer is being rate limited and when they are being denied access for another reason. It would also be beneficial to include the value `X-Rate-Limit-Remaining` header in the exception to show how low the balance is.

Making the new exception a subclass of `Forbidden` might be nice for backwards compatibility where the developer may already be handling `Forbidden` for rate limiting cases.

[Canvas docs on rate limits and throttling](https://canvas.instructure.com/doc/api/file.throttling.html)

### Additional contract requirements

- The new exception is named `RateLimitExceeded` and is available from `canvasapi.exceptions`.
- The rate-limit exception must be a subclass of `Forbidden`, so existing handlers for `Forbidden` also catch it.
- When a 403 response contains the rate-limit indicator, the exception message includes the value of the `X-Rate-Limit-Remaining` response header.
- A 403 response without the rate-limit indicator must still raise `Forbidden` and must not be raised as `RateLimitExceeded`, so callers can distinguish other access denials.
