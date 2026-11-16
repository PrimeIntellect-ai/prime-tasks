`domain='auto'` option for dsp.normalize?
## General

* pyfar version: 0.6.5

## Description

When using `pyfar.dsp.normalize()` with a FrequencyData object and default values, an error is thrown due to the default `domain='time'`. It would be nice to add an option `domain='auto'`, which checks if `signal` is a FrequencyData object.

## What I Did

```
import pyfar as pf
signal = pf.FrequencyData([1, 2, 3], [1, 2, 3])
pf.dsp.normalize(signal)
```

### Additional contract requirements

When `domain` is omitted or explicitly set to `'auto'`, `normalize` selects the domain based on the input type: it normalizes `FrequencyData` in the frequency domain and `Signal` or `TimeData` in the time domain.
