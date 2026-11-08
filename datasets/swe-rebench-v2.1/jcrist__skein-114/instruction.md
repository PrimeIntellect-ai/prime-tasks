`submit_and_connect` doesn't work on 0.4.0 when a file path is used
Need to convert spec into a `ApplicationSpec` object [HIDDEN].

### Additional contract requirements

- `Client.submit_and_connect(spec)` accepts an `ApplicationSpec`, a path to a spec file, or a spec dictionary; the specification it submits is the corresponding `ApplicationSpec`.
- Return the value produced by `self.connect(...)`.
