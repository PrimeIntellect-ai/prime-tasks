S.div argument order should match that of S.sub
Currently we have:

```haskell
sub :: FiniteNumber -> (FiniteNumber -> FiniteNumber)
sub_ :: FiniteNumber -> FiniteNumber -> FiniteNumber
```

I suggest we update [`S.div`][1] to match, giving:

```haskell
div :: FiniteNumber -> (FiniteNumber -> FiniteNumber)
div_ :: FiniteNumber -> FiniteNumber -> FiniteNumber
```

The _divide by two_ function would then be `S.div(2)` rather than `S.div(S.__, 2)`. :)


[1]: https://github.com/sanctuary-js/sanctuary/tree/v0.13.2#div

### Additional contract requirements

The divisor argument of both `S.div` and `S.div_` is a `NonZeroFiniteNumber`
(not a plain `FiniteNumber`), so the exact public type signatures are:

```haskell
div :: NonZeroFiniteNumber -> (FiniteNumber -> FiniteNumber)
div_ :: FiniteNumber -> NonZeroFiniteNumber -> FiniteNumber
```

These exact signature strings are exposed by `S.div.toString()` and
`S.div_.toString()` respectively.

`S.div` and `S.div_` throw a type error when the divisor is zero.
