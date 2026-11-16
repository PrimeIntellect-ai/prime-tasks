Track engine and storage format at dataframe & series level
Currently, `Engine` and `StorageFormat` determine the execution for new Modin objects.

We should track and propagate these values for individual dataframes, so that users can ultimately view them and change them.

### Additional contract requirements

Users can view the engine and storage-format values associated with individual dataframes and series through the `engine` and `storage_format` attributes of each object's query compiler (`obj._query_compiler`). For an object created with the Python, Ray or Dask engine and the Pandas storage format, `engine` is the name of that engine ("Python", "Ray" or "Dask") and `storage_format` is "Pandas". Users can change the values associated with newly created objects by selecting a supported engine and storage-format combination with `modin.set_execution` before creating them. Changing the selected execution does not change the engine or storage-format values already associated with existing objects.
