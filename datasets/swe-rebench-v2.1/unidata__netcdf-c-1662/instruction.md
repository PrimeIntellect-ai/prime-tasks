nc_def_var_chunking() currently ignores attempts to set chunking or filters on a scalar var - but should return error
In HDF5 chunking cannot be used on scalar vars. This results in an error on the H5Dcreate() call. So of course we don't do that.

But currently, the user can call nc_def_var_chunking() and set chunking on a scalar variable. The call ends up being ignored, due to another bug which I am just fixing WRT compact storage. So currently the user may call nc_def_var_chunking() on a scalar var, and get no error. The var, however, will be stored contiguous. nc_inq_var_chunking() will give inconsistent answers as to the storage of the var, calling it chunked for a while, but then properly identifying it as contiguous when the file is reopened.

To be consistent with the rest of the API, the nc_def_var_chunking() call should return NC_EINVAL for attempts to set chunking on a scalar variable. This will eliminate the inconsistent answers from nc_inq_var_chunking().

Since my current PR is big enough, and involves compact storage, I'll fix this as a separate PR.

### Additional contract requirements

For scalar variables, `nc_def_var_chunking()` and `nc_def_var_chunking_ints()` must return `NC_EINVAL` when asked to set chunked storage. After either rejected request, `nc_inq_var_chunking()` and `nc_inq_var_chunking_ints()` must report contiguous storage.

For scalar variables, attempts to enable filters must return an error. This includes calls to `nc_def_var_filter()` and calls to `nc_def_var_deflate()` that enable shuffle or deflate. The contract does not prescribe a particular error code.
