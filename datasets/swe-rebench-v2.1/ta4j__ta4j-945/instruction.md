Improvement: Add static `pow` method to `TransformIndicator`
For the sake of completeness, the `TransformIndicator` helper is missing a static `pow` method.

```
    public static TransformIndicator pow(Indicator<Num> indicator, Number coefficient) {
        Num numCoefficient = [HIDDEN];
        [HIDDEN]
    }
```

### Additional contract requirements

- Provide a static `TransformIndicator.pow(Indicator<Num>, Number)` factory that returns a transformed indicator whose value at each index is the corresponding source value raised to the supplied coefficient.
