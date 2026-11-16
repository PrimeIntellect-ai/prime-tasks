onBalanceVolume returns only nan
onBalanceVolume returns always NAN

The fix should be pretty simple [HIDDEN]


```
 for (let i = 1; i < result.length; i++) {
    if ([HIDDEN]) {
      result[i] = 0;
    }
    ...
```
to

```
 for (let i = 1; i < result.length; i++) {
    if ([HIDDEN]) {
      result[i] = 0;
    }
    ...
```

### Additional contract requirements

- For valid closing-price and volume inputs, `onBalanceVolume` must return a computed OBV series rather than an all-NaN result.
