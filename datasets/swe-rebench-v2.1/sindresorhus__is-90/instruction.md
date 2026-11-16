Any value in `is.numericValue` or similar?
At the moment, `is.number` returns `true` if the passed value is `NaN`. I'd quite like a function that returned `true` iff the passed value was a number with a real numeric value (`0`, `-0`, `+0`, etc. still count, `Infinity` I'd take either way (arguably `true` as Infinity is a real numeric value, just not actually countable)).

Not having yet thought about any edge cases, I imagine this would be a simple function:

```js
[HIDDEN]
```

### Additional contract requirements

Either the existing `is.number` predicate or a separate `is.numericValue` predicate must return `false` for `NaN` and `true` for numeric values including `0`, `-0`, and `+0`. The selected predicate may return either `true` or `false` for `Infinity` and `-Infinity.
