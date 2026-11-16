Large numbers in pretty printing
This is not helpful:
```
>>> let sun_luminosity = 3.828e26 W

  let sun_luminosity = 382800000000000000000000000 watt
```

### Additional contract requirements

- Integers whose absolute value is at least 100000 are printed with `_` as a thousands separator, for example `4_294_967_296`. Integers with a smaller absolute value are printed without separators, for example `1080`.
- Numbers printed in scientific notation include an explicit `+` sign for non-negative exponents, for example `8.19855e+16`.
