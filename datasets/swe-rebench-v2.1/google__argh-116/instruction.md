Clippy warnings
Derived code is triggering Clippy warnings, more specifically:

* clippy::indexing_slicing,
* clippy::panic_in_result_fn,
* clippy::str_to_string,
* clippy::unreachable,
* clippy::unwrap_in_result

Please consider using `#[automatically_derived]`/`#[allow(clippy::SOME_LINT]` or audit the codebase.

### Additional contract requirements

- When a subcommand enum is parsed with no subcommand name, both `from_args` and `redact_arg_values` must return an `EarlyExit` with `output` exactly `no subcommand name` and `status: Err(())`. When no enum variant matches the supplied subcommand name, both methods must return an `EarlyExit` with `output` exactly `no subcommand matched` and `status: Err(())`. Calling `redact_arg_values` on a subcommand struct with no subcommand name must return an `EarlyExit` with `output` exactly `no subcommand name` and `status: Err(())`.
