Deprecate requires keyword
See pypa/packaging-problems#3

If I understand correctly, at least the `requires` keyword can be safely deprecated, with its functions distributed (for now) to `setup_requires`, `install_requires` and `test_requires` as appropriate.

### Additional contract requirements

- The deprecated `requires` entry in the `[metadata]` section of `setup.cfg` remains available and is parsed as a list of requirement strings.
- A `DeprecationWarning` is emitted when the deprecated `requires` value is used.
