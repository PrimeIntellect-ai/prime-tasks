Incorrect formatting of nested tuple access
<!--
Please include the following:
- Steps and code to reproduce the problem
- Versions for Gleam, OS, the runtime and any other software used
- Logs from running Gleam with the `GLEAM_LOG` environment variable set to `trace`
-->
When formatting one of these cases:
```gleam
tuple.0.field
```
```gleam
tuple.0.1
```

It produces:
```gleam
{ tuple.0 }.field
```

Instead, it should leave them as is.
