SetContext violates the context.Context contract
In all APIs that rely on context there is no way for a callee to change the context of the caller.

Our IncomingRequest.SetContext method allows to do that. We should instead mimic the stdlib way and clone the request.

Alternatively we could explicitly pass context.Context as first parameter, but it would be quite a bit leap from the stlib api.

### Additional contract requirements

- In package `safehttp`, `IncomingRequest` must expose a method `WithContext(ctx context.Context) *IncomingRequest` that returns a shallow copy of the request whose context is `ctx`, leaving the original request unchanged. It panics if `ctx` is nil.
- In package `safehttp`, expose a function `FlightValues(ctx context.Context)` returning a value with `Put(key, value interface{})` and `Get(key interface{}) interface{}` methods. For a given request-processing context, a value inserted with `Put` must be retrievable with `Get` using the same key.
- In package `safehttp/plugins/csp`, declare a package-local type named `nonceKey` that can be used as `nonceKey{}` when storing and retrieving nonce values through `safehttp.FlightValues`.
- `IncomingRequest` must not expose the old mutating `SetContext` method. Replacing a request context must not change the context observed by the original request.
