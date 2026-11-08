Rename Only -> Select
`Select` is more inline with other implementations. Also, the opposite function `Without` should be `Unselect`?

### Additional contract requirements

- Rename `Only` to `Select` and `Without` to `Unselect` for the slice operations. Both renames are required.
- Preserve their filtering behavior: `Select` keeps elements whose predicate returns true, and `Unselect` keeps elements whose predicate returns false.
