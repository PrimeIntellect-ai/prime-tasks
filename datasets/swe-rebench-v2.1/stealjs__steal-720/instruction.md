Add npmAlgorithm: nested
Since flat will become the default in 1.0.

### Additional contract requirements

- When `npmAlgorithm` is not set in the project's `package.json`, a dependency that is installed in the top-level `node_modules` is used for a package that depends on it, even when that package also has its own nested copy of the dependency.
- Setting `"npmAlgorithm": "nested"` makes a package use its own nested copy of a dependency when one exists.
