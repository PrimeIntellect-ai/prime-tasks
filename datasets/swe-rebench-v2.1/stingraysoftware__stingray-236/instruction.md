Unhandled exception thrown in AveragedCrossspectrum constructor
If we create two lightcurves and then create an `AveragedCrossspectrum` without specifying the segment size. The following exception gets thrown: TypeError: unsupported operand type(s) for /: 'NoneType' and 'float'.

The full traceback:
```Traceback (most recent call last):
  File "\<stdin\>", line 1, in <module>
  File "\~/stingray/crossspectrum.py", line 541, in __init__
    Crossspectrum.__init__(self, lc1, lc2, norm, gti=gti)
  File "\~/stingray/crossspectrum.py", line 137, in __init__
    self._make_crossspectrum(lc1, lc2)
  File "\~/stingray/crossspectrum.py", line 606, in _make_crossspectrum
    self._make_segment_spectrum(lc1, lc2, self.segment_size)
  File "\~/stingray/crossspectrum.py", line 573, in _make_segment_spectrum
    dt=lc1.dt)
  File "\~/stingray/gti.py", line 597, in bin_intervals_from_gtis
    nbin = np.long(chunk_length / dt)
TypeError: unsupported operand type(s) for /: 'NoneType' and 'float'
```

### Additional contract requirements

When two light curves are supplied to `AveragedCrossspectrum`, `segment_size` is required. If it is omitted, construction raises `ValueError` rather than failing with the reported division `TypeError`.
