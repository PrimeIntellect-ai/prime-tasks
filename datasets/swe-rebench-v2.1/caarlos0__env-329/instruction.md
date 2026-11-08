Rename `EnvVarIsNotSetError` to `VarIsNotSetError`
The beginning of the error name is the same as the package name

### Additional contract requirements

- Rename the exported error type `EmptyEnvVarError` to `EmptyVarError`.
- `VarIsNotSetError` is an exported struct error type that implements the `error` interface and reports the name of the required environment variable that is not set. Its `Error()` method returns `required environment variable "KEY" is not set`, where `KEY` is the name of the missing variable.
- `EmptyVarError` is an exported struct error type that implements the `error` interface and reports the name of the environment variable that must not be empty. Its `Error()` method returns `environment variable "KEY" should not be empty`, where `KEY` is the name of the offending variable.
