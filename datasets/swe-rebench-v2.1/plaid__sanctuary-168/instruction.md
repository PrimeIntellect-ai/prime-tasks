Even safer parseJson
> `parseJson(Array, '{}') -> Nothing()`

I'm very fond of the `get` and `gets` style of type validation, because it forces you to do it. It would've already saved me on multiple occasions if `parseJson` (or any `x -> Any` function for that matter) had this built-in, because after doing a "safe" JSON parse, it doesn't always occur to me the return value may still be of an unwanted type.

An alternative is to extract this behaviour out to its own function, which is used solely for type validation:

```js
validate :: TypeRep -> a -> Maybe a

const parseJsonArray = compose(chain(validate(Array)), parseJson);
```

I think this second solution is more elegant in terms of modularity but it lacks the safety that comes from forcing you to do the type validation.

Side note: `TypeRep` [may be changed to a predicate](https://github.com/plaid/sanctuary/issues/149), but the idea remains the same.
