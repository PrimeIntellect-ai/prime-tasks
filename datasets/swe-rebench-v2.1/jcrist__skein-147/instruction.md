Expose absolute path of container working directory in skein.properties
There are some subtleties to determining this from environment variables, and this might be useful for other users.

See https://github.com/dask/dask-yarn/issues/49#issuecomment-456923658.

### Additional contract requirements

Expose the absolute container working-directory path as `skein.properties.container_dir` when it can be resolved from the container environment.
