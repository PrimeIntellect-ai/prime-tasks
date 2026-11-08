Momentum: Percentage Price Oscillator (PPO)
The percentage price oscillator (PPO) is a technical momentum indicator that shows the relationship between two moving averages in percentage terms. The moving averages are a 26-period and 12-period exponential moving average (EMA).

https://www.investopedia.com/terms/p/ppo.asp

### Additional contract requirements

- Add a public function `defaultPercentagePriceOscillator(prices: number[]): PercentagePriceOscillator` in module `src/indicator/momentum/percentagePriceOscillator.ts`.
- `PercentagePriceOscillator` is an object with three `number[]` fields: `ppo`, `signal`, and `histogram`.
- The default periods are fast 12, slow 26, and signal 9.
- `ppo` is `((fastEMA - slowEMA) / slowEMA) * 100`, where `fastEMA` and `slowEMA` are the 12-period and 26-period EMAs of `prices`.
- `signal` is the 9-period EMA of `ppo`, and `histogram` is `ppo - signal`.
- `ppo`, `signal`, and `histogram` each have the same length as `prices`.
- Any numeric price values are accepted, including zero and negative values.
