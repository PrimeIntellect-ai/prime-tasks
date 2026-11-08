Allow for `convolve_2d` to process in nodata areas and not mask the result
It is useful to process convolve_2d in areas with nodata, but not include those areas in the raw convolve calculation, in cases that involve weighted distance interpolation such as dilation or noise filling. This would require `[HIDDEN]` and `normalize_kernel=True` to be set in a call, but currently this raises an exception claiming an invalid use of arguments.

### Additional contract requirements

- `convolve_2d` must allow output to be computed in input nodata areas without masking those output cells, while excluding input nodata values from the convolution calculation. For nodata-hole interpolation, the combination `ignore_nodata_and_edges=True`, `mask_nodata=False`, and `normalize_kernel=True` must be accepted.
