Counter path on init is incorrect
When you run `init` it is missing the `cadence/` from the path.

### Additional contract requirements

- Generated Cadence artifacts are always placed under a `cadence/` directory. When a non-empty `rootDir` is supplied to the generator, that directory is the base and the artifacts are written to `<rootDir>/cadence/contracts/...`, `<rootDir>/cadence/scripts/...`, `<rootDir>/cadence/transactions/...`, and `<rootDir>/cadence/tests/...`. When `rootDir` is empty, the artifacts are written to `cadence/contracts/...`, `cadence/scripts/...`, `cadence/transactions/...`, and `cadence/tests/...` relative to the current directory.
- `init` must generate its Cadence files under a `cadence/` directory in the target project (for example `cadence/contracts/Counter.cdc`).
- When a generated file already exists, `Create` returns an error whose message is exactly `file already exists: <path>`, where `<path>` is the path of the existing file.
