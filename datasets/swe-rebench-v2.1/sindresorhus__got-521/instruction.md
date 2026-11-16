Regression in 7.0.0 options processing
#217 loosened unnecessary restrictions on `body` option that were discussed in #212 and allowed it to be an object that is generally considered *plain* by a developer, i.e. not a *complex* object - a buffer or a stream, which are processed differently.

#297 introduced a regression that imposed a restriction on `body` option again.

Excessive sanitization results from the use of `is-plain-obj` and restricts `body` object prototype chain to contain only  `Object.prototype` or `null`. This restriction results in counter-intuitive behaviour and requires a developer to use tricks like `Object.assign({}, obj)` instead of not doing them, even if an object is perceived as 'plain' (in my experience it was `querystring.parse()`) .

More importantly, this results in breaking changes that aren't reflected in change logs. The restrictions were dropped for a good reason, and resulting behaviour has been already relied on by package users. Now the regression just happened without an obvious reason.

### Additional contract requirements

- When the `body` option is rejected, `got` rejects with a `TypeError` whose message is exactly one of the following:
  - When `body` is not a stream, string, or Buffer and neither `json` nor `form` is set: ``The `body` option must be a stream.Readable, string or Buffer``
  - When `json` is true and `body` is not an object or array: ``The `body` option must be an Object or Array when the `json` option is used``
  - When `form` is true and `body` is not an object: ``The `body` option must be an Object when the `form` option is used``
- When `form` is true, an accepted object body is serialized as a URL-encoded query string (for example `{a: 123}` is sent as `a=123`).
