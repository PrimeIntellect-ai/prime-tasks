Allow JDs as input to `phase_to_time`
A PR brought this up as a possible enhancement to `phase_to_time`, allow the user to possibly give a float JD as another input time other than astropy.Time objects.

### Additional contract requirements

- `UVData.phase_to_time(time, phase_frame='icrs')` is a public method of the `UVData` class in the `pyuvdata` package.
- `time` may be an `astropy.time.Time` object or a float. A float is interpreted as a Julian Date.
- `phase_frame` must be either `'icrs'` or `'gcrs'`; any other value is rejected with a `ValueError`.
- The method operates in place, returns `None`, and sets the object's `phase_type` to `'phased'`.
- A `TypeError` is raised when `time` is neither an `astropy.time.Time` object nor a float.
- A `ValueError` is raised when the object's current `phase_type` is not `'drift'`.
