Filterclasses confusing state parameter
```
import pyfar as pf
filter_fir = pf.FilterFIR(coefficients=1, sampling_rate=100, state=0)
filter_fir.init_state(cshape=(1,), state='zeros')
```

In this example, the word "state" has two different meanings. First, it refers to the current state of the filter (a numpy array), and second, it refers to a configuration. This can be a bit confusing. Usually, filter objects are created using the `pyfar.dsp.filter` module, so users rarely interact with them directly.

this came up in #756

### Additional contract requirements

- `Filter` (in `pyfar.classes.filter`) exposes a public `state` property. The
  getter returns the current filter state, or `None` if no state is set. The
  setter accepts an array-like value or `None`. Setting a non-`None` state on a
  filter that has no coefficients raises a `ValueError`.
- `FilterIIR(coefficients, sampling_rate, state=None, comment="")`,
  `FilterFIR(coefficients, sampling_rate, state=None, comment="")` and
  `FilterSOS(coefficients, sampling_rate, state=None, comment="")` accept an
  optional initial `state`.
- Constructing a filter with an initial state that does not match the filter
  structure raises a `ValueError` with exactly these messages:
  - `FilterIIR`: `The state does not match the filter structure. Required shape for FilterIIR is (n_channels, *cshape, order).`
  - `FilterFIR`: `The state does not match the filter structure. Required shape for FilterFIR is (n_channels, *cshape, order).`
  - `FilterSOS`: `The state does not match the filter structure. Required shape for FilterSOS is (n_channels, *cshape, n_sections, 2).`
- When processing a signal whose channel shape does not match the stored
  state, `Filter.process` raises a `ValueError` with exactly these messages:
  - `FilterIIR`: ``The initial state does not match the cshape of the signal. Required shape for `state` in FilterIIR is (n_channels, *cshape, order).``
  - `FilterFIR`: ``The initial state does not match the cshape of the signal. Required shape for `state` in FilterFIR is (n_channels, *cshape, order).``
  - `FilterSOS`: ``The initial state does not match the cshape of the signal. Required shape for `state` in FilterSOS is (n_channels, *cshape, n_sections, 2).``
