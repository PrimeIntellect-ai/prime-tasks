Feature request: easy Filter to Signal conversion like filter.to_ir()
As a regular pyfar user, I often find the filter classes to be inconvenient. The main problems I have with filter objects are:
- They cannot be directly plotted using pf.plot functions
- so far, FilterFIR always uses direct convolution, which is almost always painfully slow compared to FFT/overlap-add convolutions
- They don't work with utilities like dsp.linear_phase()

As a consequence, I find myself writing code like the following in pretty much every script I write with pyfar:
```py
[HIDDEN]
# the actual plotting or processing I want to do with the filter
```

or for FilterFIR:
```py
filter_response = pf.Signal(filter.coefficients, filter.sampling_rate)
```

I discussed this with @f-brinkmann and we concluded that instead of changing all the plotting and utility functions to support filter objects, a convenience function for filters that converts them into a Signal object containing their impulse response would help will all of these concerns.
The method could look like this:
`filter.to_ir(target_length)`, where filter is the Filter object to convert and target_length the number of samples that the impulse response should have.
If we want more explicit naming, it could also be called `filter.to_impulse_response(len)` or similar, but this would make it less convenient to use in one-liners for plotting etc.

### Additional contract requirements

- Expose the conversion as `impulse_response(n_samples)` on filter objects. It must return a `pf.Signal` containing the filter’s impulse response with exactly `n_samples` samples.
- The returned signal must use the filter’s sampling rate.
