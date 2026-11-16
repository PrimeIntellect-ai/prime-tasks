Trend: Trix (TRIX)
The triple exponential average (TRIX) indicator is an oscillator used to identify oversold and overbought markets, and it can also be used as a momentum indicator. Like many oscillators, TRIX oscillates around a zero line.

https://www.investopedia.com/articles/technical/02/092402.asp

### Additional contract requirements

- Expose the indicator as a package-level callable `trix(period: number, values: number[]): number[]` function.
- Return a TRIX series with the same length as `values`; its first value is zero, and each subsequent value is the rate of change of the triple-smoothed EMA series from the previous bar, expressed as a decimal proportion (for example, `0.05` for a 5% increase), not multiplied by 100.
