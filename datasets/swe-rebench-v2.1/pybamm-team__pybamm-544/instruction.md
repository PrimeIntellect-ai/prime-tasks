Better errors for ProcessedVariable
Raise clear error when the wrong arguments are passed to `ProcessedVariable.__call__`. Currently a bit obscure when it fails.

### Additional contract requirements

- For a macroscale variable with at least two dimensions, calling `ProcessedVariable.__call__` without `x` must raise a `ValueError` that identifies `x` as missing.
- For a microscale variable with at least two dimensions, calling `ProcessedVariable.__call__` without `r` must raise a `ValueError` that identifies `r` as missing. This includes calls that provide a time and a second positional value but no `r`.
