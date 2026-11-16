can't pickle dict_keys objects
Using Dask.distributed, which uses cloudpickle for serialization, I encounter an error when passing a `dict_keys` object as a parameter to a function.  I reported the issue [there](https://github.com/dask/distributed/issues/3893), where it was suggested that I also report an issue here for consideration.

As a test, I attempted to use cloudpickle directly on this type of object and received the following error:
`TypeError: can't pickle dict_keys objects`

Would it be possible to add the ability to pickle `dict_keys` object?
