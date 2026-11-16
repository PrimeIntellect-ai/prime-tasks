Add option to never write fill value via the high-level dataset creation interface
This is not a bug report.

Since this is my first issue here, I just want to take this chance to thank all the developers in `h5py` for providing this convenient Python wrapper for hdf5!

#### Background
For parallel writing to chunked storage, the chunks are allocated when the dataset is created and in `h5py` [it enforces the time of writing fill value on allocation](https://github.com/h5py/h5py/blob/master/h5py/_hl/filters.py#L262). From the comment there I guess it is to ensure all values have been properly initialised to avoid reading uninitialised memory. However, this is unnecessary when we know we are definitely going to overwrite all the fill values in our whole dataset by our actual data.

#### Current limitation
I found out [you can pass your dataset creation property list using the keyword `dcpl`](https://github.com/h5py/h5py/blob/master/h5py/_hl/dataset.py#L39) from `create_dataset`, so potentially I can use the `set_fill_time` method to change it to `FILL_TIME_NEVER` for my own dcpl, however it will be [overwritten by `FILL_TIME_ALLOC`](https://github.com/h5py/h5py/blob/master/h5py/_hl/filters.py#L262) later. Another route is to bypass the high-level interface entirely by using the exposed C API, but I will miss all the validations provided to other settings.

#### Suggestion
I would like to suggest exposing the option of never writing fill values via the high-level `create_dataset`/`require_dataset` interface. One way of doing it is to provide a parameter in those methods, such as something like `write_fill` with options `"alloc"`/`"never"`/`"ifset"` ([the current options in hdf5](https://docs.hdfgroup.org/hdf5/v1_14/_h5_dpublic_8h.html#aa39293626c4e68dd28b06c0dc84bde4a)), default it to `"alloc"` and this will keep the original behaviour. By consciously passing `write_fill="never"`, the user is aware of and responsible for this.

[HIDDEN]

#### Potential action
[Setting the fill time to `H5D_FILL_TIME_NEVER` can have significant performance improvement for parallel writing to chunked storage](https://www.hdfgroup.org/wp-content/uploads/2022/05/2022_ECP-Parallel-HDF5-Performance-Tuning.pdf). I hope this can benefit users who know they will definitely overwrite the fill values by their data. I am more than happy to contribute to this if `h5py` developers are happy about this idea and this won't cause significant safety and security issues.

Thank you.

Useful link:
[Storage allocation and fill summary](https://docs.hdfgroup.org/hdf5/v1_14/_h5_d__u_g.html#subsubsec_dataset_allocation_store)

### Additional contract requirements

- The `fill_time` option defaults to the HDF5 library default, `IFSET`. When `fill_time` is omitted (or `None`), the created dataset's fill time is `IFSET`, not `ALLOC`.
- The option is exposed through both `create_dataset` and `require_dataset`.
