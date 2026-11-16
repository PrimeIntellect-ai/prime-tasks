PyPREP excludes interpolated NaN/flat/low-SNR channels from average referencing
While pulling together a fix for #77, I ended up catching another PyPREP/MatPREP difference I didn't notice before. Essentially, PyPREP re-uses [HIDDEN], which ends up causing any channels flagged as bad-by-SNR, bad-by-NaN, or bad-by-flat on the initial NoisyChannels pass to be excluded from the average reference signal even after they've been interpolated.

Specifically, the `[HIDDEN]` here:

https://github.com/sappelhoff/pyprep/blob/6abe0bcf1d1d40aefd2fe4cc41b200fbb0924ee4/pyprep/reference.py[HIDDEN]

[HIDDEN]

https://github.com/sappelhoff/pyprep/blob/6abe0bcf1d1d40aefd2fe4cc41b200fbb0924ee4/pyprep/reference.py[HIDDEN]

whereas in MATLAB PREP [HIDDEN].

### Additional contract requirements

The average reference signal is available as `Reference.reference_signal` after
calling `Reference.perform_reference()`. It must be computed over all channels
listed in `params["ref_chs"]`, including channels that were interpolated because
they were initially flagged as bad by NaN, flat, or low SNR.
