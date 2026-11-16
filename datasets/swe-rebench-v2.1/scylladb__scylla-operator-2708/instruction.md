`scyllaArgs` not accepting flags without values
`scyllaArgs` expects every `--flag` to have a value and mangles flags without values by adding an empty value to them.

This does not work with `--poll-mode` for which ScyllaDB expects no value, but Operator appends an empty string `""` value, causing ScyllaDB to fail to start up.

https://github.com/scylladb/scylla-operator/blob/master/pkg/sidecar/config/config.go#L191-L199

## Acceptance Criteria

- [ ] `--poll-mode` works if passed in `scyllaArgs`

### Additional contract requirements

- Presence-only flags supplied through `scyllaArgs` must remain valueless in the final ScyllaDB command line; they must not be emitted with an empty value.
- When `--poll-mode` is passed in `scyllaArgs`, the final ScyllaDB command line must include it as a standalone argument, not as `--poll-mode=`.
