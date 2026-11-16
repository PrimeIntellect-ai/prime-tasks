Change nc_inq_var_deflate()/nc_inq_var_szip() to return NC_NOERR for non-HDF5 files, reporting compression off
In the 4.7.4 release, attempts to read the deflate level of a var in a classic file return an NC_ENOTNC4 error.

However, historically, the function returned a deflate level of 0 for that var.

Whether this make sense or not is less clear. If you think of deflate as invariably liked to filters, then it make sense to return failure. However, if you think of deflate as a compression algorithm that could be applied to multiple dispatch layers. then it makes sense  to return 0 for those dispatch layers that don't support deflate.
