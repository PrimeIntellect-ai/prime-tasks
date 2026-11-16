Bug in `Powerspectrum` when GTI is shorter than light curve?
I have a data set where the GTIs are slightly shorter than the data in the FITS file. When I create a light curve and then try to use `Powerspectrum`, I get an AssertionError that no GTIs are longer than `segment_size`. I think this is a bug where `Powerspectrum` internally sets `segment_size` to whatever the length of the data is, and when that's passed on to the code that checks the GTIs, it finds no GTI that is the length of the data. I think this should internally set the segment_size to the length of the GTI, rather than fail.

Minimum example:
```
import numpy as np
from stingray import Lightcurve, Powerspectrum

tstart = 1.0
tend = 10.0
gti = [[1.0, 9.0]]

time = np.linspace(tstart, tend, 10000)
counts = np.random.poisson(10, size=time.shape[0])

lc = Lightcurve(time, counts, gti=gti)
ps = Powerspectrum(lc, norm="leahy")
```

Last part of output:
```
File /opt/miniconda3/envs/qpogp/lib/python3.9/site-packages/stingray-1.0-py3.9.egg/stingray/gti.py:1257, in bin_intervals_from_gtis(gtis, segment_size, time, dt, fraction_step, epsilon)
   1252     newbins = calculate_segment_bin_start(
   1253         startbin, stopbin, nbin, fraction_step=fraction_step)
   1254     spectrum_start_bins = \
   1255         np.append(spectrum_start_bins,
   1256                   newbins)
-> 1257 assert len(spectrum_start_bins) > 0, \
   1258     ("No GTIs are equal to or longer than segment_size.")
   1259 return spectrum_start_bins, spectrum_start_bins + nbin

AssertionError: No GTIs are equal to or longer than segment_size.
```

### Additional contract requirements

- Add a public function `avg_pds_from_timeseries(times, gti, segment_size, dt, fluxes=None, errors=None, norm="leahy", silent=False, return_subcs=False, use_common_mean=False, return_err=False, return_unnorm=False, return_dt=False, **kwargs)` in module `stingray.fourier`. It computes an averaged periodogram from a single time series (an event list or a binned light curve). It returns a table containing the frequency and power, with metadata that includes the keys `"segment_size"` and `"dt"`, or `None` when the input cannot produce a periodogram. It accepts non-integer `segment_size` values and adjusts them to an integer number of samples. When `segment_size` is `None`, the full GTI is used.
- Add a public function `avg_cs_from_timeseries(times1, times2, gti, segment_size, dt, fluxes1=None, fluxes2=None, errors1=None, errors2=None, norm="leahy", silent=False, return_subcs=False, use_common_mean=False, return_err=False, return_unnorm=False, return_dt=False, **kwargs)` in module `stingray.fourier`. It computes an averaged cross-spectrum for two time series and returns a table whose metadata includes the keys `"segment_size"` and `"dt"`, with the same non-integer segment-size handling and `segment_size=None` behaviour as `avg_pds_from_timeseries`.
- The functions `avg_pds_from_events` and `avg_cs_from_events` in module `stingray.fourier` are deprecated: calling either of them emits a `DeprecationWarning`.
