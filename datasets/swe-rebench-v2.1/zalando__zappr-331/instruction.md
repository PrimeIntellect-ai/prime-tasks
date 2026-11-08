Add middleware for application/problem+json
In API handlers we should be able to throw a certain error instance that will be picked up by this middleware. It should also handle generic errors. All errors should be converted to satisfy the [application/problem+json RFC](https://tools.ietf.org/html/rfc7807#section-3), so that our frontend can handle errors in a generic way.

### Additional contract requirements

- Add a public function `symbolToString(sym)` in `common/util.js`. When `sym` is a JavaScript `Symbol`, it returns the symbol's description as a string (for example `Symbol('foo')` becomes `'foo'`); for any other value it returns that value unchanged.
- Add a public function `generateProblemResponseFromAppError(e)` in `server/middleware/problem.js`. It returns a plain object describing an RFC 7807 problem:
  - `status` is taken from `e.status` or `e.statusCode`, and defaults to `500`.
  - `title` is taken from `e.title` or `e.message`, and defaults to `"Internal server error"`.
  - `detail`, `instance` and `type` are included when present; a `Symbol` `type` is converted to its description string, and a string `type` is kept as is.
  - Every other enumerable key of `e` is copied to the result as a top-level property.
  - The internal fields `expose` and `statusCode` are not present in the result.
- Add a middleware factory, exported as the default export of `server/middleware/problem.js`, that returns a Koa middleware. When a downstream handler throws an error, the middleware responds with `Content-Type: application/problem+json`, the HTTP status taken from `status` or, when absent, `statusCode`, and a problem-JSON body.
