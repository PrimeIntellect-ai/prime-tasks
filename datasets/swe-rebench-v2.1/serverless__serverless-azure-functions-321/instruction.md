Invoke throws 400 error when using `-p` option
Invoke works fine when using `-d` and passing the stringified JSON, but fails when using a path to sample data

### Additional contract requirements

- When the `path` option refers to a file that does not exist, invoking the function must fail with an error raised at invocation time. The plugin must not raise this error while it is being constructed.


- When no HTTP method is specified, invocation must use `GET`.
