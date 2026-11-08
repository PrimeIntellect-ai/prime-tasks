RSI returns `NaN` array
## Describe the bug

`customRsi` / `rsi` returns `NaN` array.

## To Reproduce

Run:

```javascript
customRsi(14, Array.from(Array(100).keys()))
```

## Expected behavior

RSI should return expected results.

### Additional contract requirements

- For the closings `[10, 12, 11, 11, 14, 16, 18, 17, 18, 19, 16, 14, 14, 15, 16, 19, 20, 22]`, `customRsi(14, closings)` must produce the following results when rounded to two decimal places: `[0, 100, 66.67, 66.67, 83.33, 87.5, 90, 81.82, 83.33, 84.62, 68.75, 61.11, 61.11, 63.16, 65.13, 70.28, 71.78, 74.54]`.
