Support a backtrace
People like backtraces.

My idea is to support a field called `backtrace`. If it's present, it will be automatically constructed when `From::from` or `fail` is called.

One trick will be to decide how best to have forwards-compatibility. Eventually, the standard library will have such a type and it will accessible via the `Error` trait, but it's not there today. We'd prefer to be able to be able to seamlessly upgrade.

My thought is to have a newtype for the backtrace crate that doesn't expose much in the way of an API. We can then add an inherent method on the `Error` enum with the proposed API for `std::error::Error`.

Things to check / consider:

- What happens when `std::error::Error` gains the method; will that cause conflicts?
- Do we need multiple ways to specify what the backtrace is? (see #10)

### Additional contract requirements

- Export a narrow backtrace wrapper named `Backtrace`. It must support automatic construction for a declared error field named `backtrace` when an error is created through `From::from` or `fail`.
- Expose `ErrorCompat::backtrace(&self) -> Option<&Backtrace>` so callers can retrieve a carried backtrace; return `None` for an error that does not carry one.
- Keep the retrieval API forward-compatible with the standard error API: callers must be able to use the Snafu backtrace accessor without blocking or conflicting with a same-named backtrace accessor on `std::error::Error` when that API is available.
