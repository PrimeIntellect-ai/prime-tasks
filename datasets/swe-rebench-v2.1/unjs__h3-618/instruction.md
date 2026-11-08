`xForwardedFor` returns the last IP address in the `X-Forwarded-For` header
### Environment

Node: v18.16.0
h3 1.9.0

### Reproduction

Call `getRequestIP(event, { xForwardedFor: true })` in an application behind a proxy server.

### Describe the bug

When calling `getRequestIP(event, { xForwardedFor: true })`, the last IP address in the list is returned instead of the first one (the client's IP address), when I assume the first one should be.

### Additional context

_No response_

### Logs

_No response_
