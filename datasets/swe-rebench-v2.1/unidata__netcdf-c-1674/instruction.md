nc_inq_var_deflate() no longer returns 0 for deflate_level when deflate is not in use
Although there was no test for this in the C library, netcdf-fortran tests depend on 0 being returned for deflate_level when deflate is not in use. This used to be the case, but is no longer happening.

I will submit a PR shortly.
