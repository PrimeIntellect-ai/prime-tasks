mapMaybe :: (a -> Maybe b) -> [a] -> [b]
<https://hackage.haskell.org/package/base-4.8.1.0/docs/Data-Maybe.html#v:mapMaybe>:

> The `mapMaybe` function is a version of `map` which can throw out elements. In particular, the functional argument returns something of type `Maybe b`. If this is `Nothing`, no element is added on to the result list. If it is `Just b`, then `b` is included in the result list.

### Additional contract requirements

- Add a public function `S.mapMaybe :: (a -> Maybe b) -> [a] -> [b]` to the Sanctuary library, exported as `S.mapMaybe`.
- `mapMaybe` is binary and curried: `S.mapMaybe(fn)` returns a unary function awaiting the list.
- The second argument is an Accessible (array-like) collection and must not be `null` or `undefined`.
- `mapMaybe` throws a `TypeError` when the first argument is not a function, or when the second argument is `null` or `undefined`.
- `mapMaybe` returns a new list containing the values extracted from each `Just` result; entries for which the function returns `Nothing` are omitted.
