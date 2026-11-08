eitherToMaybe :: Either a b -> Maybe b
@kedashoe added [`maybeToEither`][1] in #76. It would be nice to provide a function for going in the other direction. The implementation is not complex, and already appears in the [test suite][2]:

> ```javascript
> //  eitherToMaybe :: Either a b -> Maybe b
> [HIDDEN]
> ```


[1]: http://sanctuary.js.org/#maybeToEither
[2]: https://github.com/sanctuary-js/sanctuary/blob/v0.10.0/test/index.js#L117-L118

### Additional contract requirements

- For a `Left`, return `Nothing`.
- For a `Right`, return `Just` containing its value.
