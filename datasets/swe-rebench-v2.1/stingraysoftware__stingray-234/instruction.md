Shouldn't rebin and rebin_log both return `*Spectrum`s?
As things are now, `Crossspectrum.rebin` returns a `Crossspectrum` object while `Crossspectrum.rebin_log` returns a tuple (frequency, power, number). Is there a specific reason for this? Shouldn't they return the same kind of value (preferably a `Crossspectrum`?)

### Additional contract requirements

The returned spectrum contains frequency and power arrays representing the logarithmically rebinned data.
