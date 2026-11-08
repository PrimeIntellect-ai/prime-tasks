Supertrend Indicator
**I have checked existing issues and wiki**
- [x] I could not find similar [issues](https://github.com/ta4j/ta4j/issues?utf8=%E2%9C%93&q=)
- [ ] I could not find a solution in the [wiki](https://ta4j.github.io/ta4j-wiki/) or [faq section](https://ta4j.github.io/ta4j-wiki/FAQ.html)

Is it possible to add the Supertrend indicator?
I found a beginning of the solution in https://stackoverflow.com/questions/68063996/java-implementation-of-supertrend

Thank you

### Additional contract requirements

Add the following public indicators in the package `org.ta4j.core.indicators.supertrend`:

- `SuperTrendIndicator` with a public constructor `SuperTrendIndicator(BarSeries series)` that uses the default ATR length 10 and multiplier 3.
- `SuperTrendLowerBandIndicator` with a public constructor `SuperTrendLowerBandIndicator(BarSeries barSeries)` that uses the default ATR period 10 and multiplier 3.
- `SuperTrendUpperBandIndicator` with a public constructor `SuperTrendUpperBandIndicator(BarSeries barSeries)` that uses the default ATR period 10 and multiplier 3.

Each indicator exposes its value at a bar index through the standard `getValue(int index)` method, returning a `Num`.

The reference bar series consists of the following bars in chronological order. Indices are zero-based, and each row gives the open, high, low, and close:

| Index | Open | High | Low | Close |
|---:|---:|---:|---:|---:|
| 0 | 21.48 | 23.39 | 21.35 | 23.17 |
| 1 | 19.94 | 21.29 | 20.07 | 21.25 |
| 2 | 21.97 | 24.30 | 20.01 | 20.08 |
| 3 | 20.87 | 22.64 | 20.78 | 22.17 |
| 4 | 21.65 | 22.80 | 21.59 | 21.67 |
| 5 | 22.14 | 22.26 | 20.96 | 21.47 |
| 6 | 21.44 | 22.31 | 21.36 | 22.25 |
| 7 | 21.67 | 22.40 | 21.59 | 21.83 |
| 8 | 22.90 | 23.76 | 22.73 | 23.09 |
| 9 | 22.01 | 23.27 | 21.94 | 22.93 |
| 10 | 19.20 | 20.47 | 18.91 | 19.89 |
| 11 | 18.83 | 21.80 | 18.83 | 21.56 |
| 12 | 18.35 | 19.41 | 18.01 | 19.00 |
| 13 | 6.36 | 20.22 | 6.21 | 19.89 |
| 14 | 10.34 | 20.58 | 10.11 | 19.28 |

For this reference bar series, the indicators must return:

- `SuperTrendIndicator`: 15.730621000000003 at index 4, 17.602360938100002 at index 9, and 22.78938583966133 at index 14.
- `SuperTrendLowerBandIndicator`: 15.730621000000003 at index 4, 17.602360938100002 at index 9, and 2.4620527443048026 at index 14.
- `SuperTrendUpperBandIndicator`: 26.610999999999997 at indices 1 and 6, and 24.67820648851259 at index 12.
