`subtract_overscan` incorrectly allows a numpy array as input
See https://github.com/astropy/ccdproc/blob/main/ccdproc/core.py#L478

Both the docstring and code later in the function clearly assumes the thing passed in is a `CCDData` object.
