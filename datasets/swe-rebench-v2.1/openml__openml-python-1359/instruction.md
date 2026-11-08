[Feature] Environment variable for openml cache
This could be useful in certain scenarios where you may have programmatic access before running something but during the execution of the python script, you do not have access to it.

I would recommend something like `"OPENML_CACHE_DIRECTORY"`?

### Additional contract requirements

- The environment variable that controls the OpenML cache location is named `OPENML_CACHE_DIR`.
