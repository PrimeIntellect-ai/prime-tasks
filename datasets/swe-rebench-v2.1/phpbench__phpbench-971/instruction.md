Option/default to strip tailing zeros when displaying numbers.K
For example:

```
1,000.000μs
```

requires more effort to parse than:

```
1,000μs
```

We should strip "padding" zeros from the end of numbers.

### Additional contract requirements

Expose a boolean configuration option named `expression.strip_tailing_zeros` for displayed numeric output. When enabled, displayed numbers omit insignificant trailing zeros in the fractional part while retaining the numeric value and meaningful integer zeros; when disabled, fractional padding remains visible.
