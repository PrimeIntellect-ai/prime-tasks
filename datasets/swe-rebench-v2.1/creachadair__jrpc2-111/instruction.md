Allow "Content-Type: application/json; charset=utf-8"
Currently it looks like only "application/json" is allowed by jrpc2's handler - https://github.com/creachadair/jrpc2/blob/main/jhttp/bridge.go#L60

We would like to allow "application/json; charset=utf-8" too since some of our partners use that request type.

### Additional contract requirements

- The `charset` parameter of an `application/json` `Content-Type` is accepted
  when its value is either `utf-8` or `utf8`.
- A request whose `Content-Type` is `application/json` but whose `charset`
  parameter has any other value is rejected with HTTP status 415 (Unsupported
  Media Type) and a response body of exactly `invalid content-type charset\n`.
