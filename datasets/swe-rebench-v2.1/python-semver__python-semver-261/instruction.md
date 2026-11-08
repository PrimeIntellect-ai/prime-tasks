__getitem__ returns `None` for version parts that are falsy
For example, VersionInfo(0, 1, 0, 'r.1')[2] returns None when it should return 0.

### Additional contract requirements

- `VersionInfo.__getitem__(index)` accepts a non-negative integer or a `slice` object and returns the corresponding version component(s).
- A positive integer index returns the component at that position (major, minor, patch, prerelease, or build).
- A slice returns the selected components: a single value when exactly one defined component is selected, otherwise a tuple.
- A negative integer index or a slice with a negative bound raises `IndexError` with the message "Version index cannot be negative".
- A positive index or slice that resolves to no defined component raises `IndexError` with the message "Version part undefined".
