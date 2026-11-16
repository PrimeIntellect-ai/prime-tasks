Got 9.0.0 throws when using unescaped characters
With Got 9.0.0,
```
require("got")("http://google.com/search", { query: { q: "friend’s house" } })
   .then(() => console.log("ok"))
```
rejects with:
```
(node:27956) UnhandledPromiseRejectionWarning: RequestError: Request path contains unescaped characters
    at EventEmitter.cacheReq.on.error (node_modules/got/source/request-as-event-emitter.js:105:27)
    at EventEmitter.emit (events.js:182:13)
    at makeRequest (node_modules/cacheable-request/src/index.js:125:9)
    at get (node_modules/cacheable-request/src/index.js:135:14)
    at process._tickCallback (internal/process/next_tick.js:68:7)
```

With `got@8.3.2` this snippet works just fine.

### Additional contract requirements

- For a query parameter value of `it’s ok`, Got must encode the request URL value as `it%E2%80%99s+ok` (for example, `{test: 'it’s ok'}` produces `/?test=it%E2%80%99s+ok`).
- Got must follow a redirect whose `Location` header contains a URI-encoded URL (for example, a `Location` of `/?test=it%E2%80%99s+ok`) and reach the redirect target, instead of rejecting the request.
