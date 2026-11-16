`iso8601.iso8601.Utc` is not reliably available
Version 0.1.12 doesn't expose this for Python 3.2.0 and newer, it looks like this is not really a public export anyway and we ought to be using `UTC` which is an instance of a UTC tzinfo implementation.

### Additional contract requirements

- `UTC` is a public name in `iso8601.iso8601`. It is a tzinfo instance (not a
  function or class), so it is used directly as a timezone value rather than
  being called.
