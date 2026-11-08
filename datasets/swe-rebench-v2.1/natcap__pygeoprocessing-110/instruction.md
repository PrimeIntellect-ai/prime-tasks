convolve 2d bug?
This is from @dcdenu4: https://drive.google.com/file/d/1R3QsQGQCud6-QNjtbodaz6fm5mawliu6/view?usp=sharing

Summary
=======

When running ``pygeoprocessing.convolve_2d`` on a raster with patched values
surrounded my nodata values ( like spots on a cow ) the output is corrupt.
When replacing the nodata values for that raster with 0s, the output is as
expected.

Files
=====

* convolution-bug-script.py
    A python script with the paths defined to replicate the issue. This calls
    ``convolve_2d`` on ``urban_c_aligned.tif`` and ``kernel_urban_c.tif``.
    The output is ``output_convolution.tif``.
* kernel_urban_c.tif
    The exponential kernel for convolution.
* urban_c_aligned.tif
    The raster with patchy values of 1 and otherwise nodata values. Nodata
    value is 0
* urban_c_aligned_zeros.tif
    The same raster as ``urban_c_aligned.tif`` except nodata has been set to -9
    and original nodata values are now 0s

### Additional contract requirements

Convolving a signal with patchy valid values surrounded by nodata must not produce corrupt output. If a call that ignores nodata and edges without masking nodata returns an output, its result must match convolution of the same signal after replacing its nodata cells with zero. Rejecting that option combination is also acceptable. When `mask_nodata` is true, output pixels at nodata locations in the signal raster must be nodata.
