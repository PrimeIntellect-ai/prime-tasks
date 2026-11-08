Inconsistency for fractional filter returns
[fractional_octave_bands](https://pyfar.readthedocs.io/en/stable/modules/pyfar.dsp.filter.html#pyfar.dsp.filter.fractional_octave_bands) and [reconstructing_fractional_octave_bands](https://pyfar.readthedocs.io/en/stable/modules/pyfar.dsp.filter.html#pyfar.dsp.filter.reconstructing_fractional_octave_bands) have different output parameter

seems like ``reconstructing_fractional_octave_bands``returns signal, frequencies or filter, frequencies
and ``fractional_octave_bands`` returns signal or filter


also the inputs are not perfect. the ``sampling_rate`` is not at the same position and ``num_fractions`` has sometimes defaults and another time not.
```
pyfar.dsp.filter.reconstructing_fractional_octave_bands(signal, num_fractions=1, frequency_range=(63, 16000), overlap=1, slope=0, n_samples=4096, sampling_rate=None)

pyfar.dsp.filter.fractional_octave_bands(signal, num_fractions, sampling_rate=None, frequency_range=(20.0, 20000.0), order=14)
```

### Additional contract requirements

- The deprecation warning is a `pyfar.classes.warnings.PyfarDeprecationWarning`
  and its message is exactly:
  "Return parameter 'frequencies' will be removed in pyfar 0.9.0. To get the fractional octave center frequencies, use `pyfar.dsp.filter.fractional_octave_frequencies` instead."
- The center frequencies are still returned as the last element of the result
  tuple, both when `signal` is `None` (returning the filter object) and when a
  signal is filtered. These center frequencies equal the exact center
  frequencies returned by `pyfar.dsp.filter.fractional_octave_frequencies` for
  the same `num_fractions` and `frequency_range`.

- This deprecation change does not harmonize the two functions' input APIs.
  Their existing conventions remain: `reconstructing_fractional_octave_bands`
  defaults `num_fractions` to 1 and places optional `sampling_rate` last, while
  `fractional_octave_bands` requires `num_fractions` and places optional
  `sampling_rate` immediately after it.
