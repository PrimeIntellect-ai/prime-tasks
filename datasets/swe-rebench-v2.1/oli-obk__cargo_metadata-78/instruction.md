Consider switching to a error type which is `Sync`
Consider switching to a error type which is `Sync` (so that it can be turned into a `Failure` error).

`Fail` requires `Send`+`Sync`+`'static` but error chain errors are not `Sync` (due to the way they handle backtraces if I remember correctly).

### Additional contract requirements

- The public `Error` type must implement `failure::Fail`, so that an `Error` value can be converted into a `failure::Error` (for example via `Into::into` or the `?` operator). This is in addition to `Error` being `Send + Sync + 'static`.


- When `Error::CargoMetadata { stderr: "boom" }` is converted into `failure::Error`, formatting the converted value with `Display` must contain `boom`.
