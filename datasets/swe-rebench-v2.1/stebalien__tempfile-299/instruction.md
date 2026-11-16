feature: `with_suffix` to correspond to `with_prefix`
Stumbled upon while trying to wrangle some integration testing for a CLI tool, which expects a specific filetype. `with_prefix` adds a short string to the start of a file's name. We can alter this very cleanly by simply doing some plumbing for adding a short string to the end of the file's name, instead. [HIDDEN]

### Additional contract requirements

- `with_suffix` and `with_suffix_in` must be provided on both `NamedTempFile` and `TempDir`, mirroring the existing `with_prefix` and `with_prefix_in` constructors. A temporary file or directory created with a supplied suffix must have a name ending with that suffix, and the `_in` variant must create it inside the supplied directory.
