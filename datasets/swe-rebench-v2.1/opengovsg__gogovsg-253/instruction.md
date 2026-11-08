Fix bug where GA cookie is set after a server redirect
**Describe the bug**
When a new visitor without a GA cookie visits a short link, the server attempts to set a cookie after a response has already taken place. This results in a HTTP 500 Internal Server Error being logged when in fact a HTTP 302 Redirect has already been returned to the client.

**To reproduce**
Steps to reproduce the behavior:
1. Clear cookies
2. Visit a short link
3. Verify that browser is redirected successfully
4. Observe stack trace and HTTP 500 in logs

### Additional contract requirements

- The analytics logger's redirect-logging method takes the incoming request, the short URL, and the long URL, and returns nothing; it no longer takes the response object.
- The short URL is lower-cased before it is logged.
- The analytics logger exposes a method `generateCookie(cookie?: string)` that returns the GA client-id cookie settings when the visitor has no GA cookie, and nothing when the visitor already has one.
- For a visitor without a GA cookie, the GA client-id cookie (named `gaClientId`) is set on the response before the redirect response is sent.
