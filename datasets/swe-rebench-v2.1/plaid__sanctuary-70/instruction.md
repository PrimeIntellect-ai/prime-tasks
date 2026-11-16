integer type
This may or may not be useful:

```javascript
> S.Int(7).add(S.Int(2))
Int(9)
> S.Int(7).divideBy(S.Int(2))
Int(3)
> S.Int(7).valueOf()
7
```

An integer type would allow us to specify types more precisely. [`S.at`][1], for example, could have type `Int -> [a] -> Maybe a`.


[1]: https://github.com/plaid/sanctuary#at

### Additional contract requirements

An Integer is a JavaScript number with no fractional part whose value lies strictly between -2^53 and 2^53. Integer validation applies to the integer-specific arguments of `at`, `slice`, `take`, `takeLast`, `drop`, `dropLast`, and `parseInt`; `parseInt` returns `Nothing` for values outside this range.
