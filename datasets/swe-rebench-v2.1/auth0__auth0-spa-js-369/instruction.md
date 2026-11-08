Throw Explicit errors on failure when bootstrapping
At the moment if wrong arguments are passed or for some reason, the authorization server fails to respond catastrophically the library will timeout and return an object.

https://github.com/auth0/auth0-spa-js/blob/master/src/index.ts#L43

It'd be better to throw an error when initializing with `createAuth0Client` and let the apple handle what it must do when AS is unavailable. This might also be helpful when initially setting up (eg: Point to docs in dev bundle?)

### Additional contract requirements

- Errors with `error: 'login_required'` are absorbed. For an initialization error with `error: 'some_other_error'`, `createAuth0Client` must throw an object whose `.error` is `'some_other_error'`.
