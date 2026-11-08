HDF5 error when unlimited dimension and a variable share the same name
Reported by a python user (https://github.com/Unidata/netcdf4-python/issues/975).  The error occurs when a variable has the same name as an unlimited dimension, but does not have an unlimited dimension.  Both C and python programs to trigger the error included in the python issue.
