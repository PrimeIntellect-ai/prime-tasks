Need the ability to configure NativeQueryCompiler with environment variables
We have several class variables in the native query compiler which should be configurable.

### Additional contract requirements

- `NativeQueryCompiler` is the class `modin.core.storage_formats.pandas.native_query_compiler.NativeQueryCompiler`; it can be constructed from a pandas DataFrame.
- `NativeQueryCompiler._engine_max_size()` is a class method returning an `int`: the maximum number of rows the native pandas engine is allowed to handle. For `NativeQueryCompiler` itself it returns the value of the `NativePandasMaxRows` configuration variable.
- `NativeQueryCompiler._transfer_threshold()` is a class method returning an `int`: the row count at which transferring data between engines is considered. For `NativeQueryCompiler` itself it returns the value of the `NativePandasTransferThreshold` configuration variable.
- `NativePandasMaxRows` and `NativePandasTransferThreshold` are configuration variables in `modin.config.envvars`. They are configured through the environment variables `MODIN_NATIVE_MAX_ROWS` and `MODIN_NATIVE_MAX_XFER_ROWS` respectively.
- A `NativeQueryCompiler` instance exposes `_TRANSFER_THRESHOLD == 0` and `_MAX_SIZE_THIS_ENGINE_CAN_HANDLE == 1`. A subclass of `NativeQueryCompiler` that does not override these attributes exposes the same values.
