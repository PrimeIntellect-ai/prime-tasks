FEAT Add option to disable timeout
An option to disable the timeout would be great (`--timeout -1` for instance).

### Additional contract requirements

- `benchopt run` accepts a `--no-timeout` flag that disables any timeout
  enforcement for the solvers. It is mutually exclusive with `--timeout`:
  supplying both raises `click.BadParameter`.
- The configuration setting `default_timeout` (default value `100`) is
  available and is used as the timeout when no explicit `--timeout` is given.
- `benchopt.config.parse_value(value, default_value)` converts a textual
  `value` to the type of `default_value`, supporting integer and float
  defaults in addition to the existing boolean and list handling.
