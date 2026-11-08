RSI indicator should have the unstableBars() equals to barCount
https://github.com/ta4j/ta4j/blob/1101dbe059cda92d7dd1f86e755b0466782911d5/ta4j-core/src/main/java/org/ta4j/core/indicators/RSIIndicator.java#L71

### Additional contract requirements

- `org.ta4j.core.indicators.RSIIndicator.getCountOfUnstableBars()` returns the configured `barCount`.
- `org.ta4j.core.indicators.StochasticRSIIndicator.getCountOfUnstableBars()` returns the configured `barCount`.
- For both indicators, `getValue(i)` returns `NaN` for indices `i` from `0` through `barCount - 1`.
- With `barCount` 3, `StochasticRSIIndicator.getValue(3)` returns `NaN` for input data `[10, 15, 10, 15, 10]` and `[10, 20, 20, 20]`.
