Add res properties to custom props
The function `reqCustomProps` only has access to the `req` object, but best practice is to store data scoped to the request in `res.locals`, to which there is no access in `reqCustomProps`.
Does `res.locals` automatically get logged?
If not I'd be happy to open a pull request as it seems like [HIDDEN], it should have minimal impact on current users' implementations.

### Additional contract requirements

- The `reqCustomProps(req, res)` callback must receive the request and its corresponding response, so callers can use response-scoped data such as `res.locals` when producing custom properties.
- The callback’s returned properties are included in the request log entry; `res.locals` is not automatically logged merely because it is present on the response.
