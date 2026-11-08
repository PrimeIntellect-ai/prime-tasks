Solver does not consider provided package version in provides entries
Consider the following repository:

- `a-1-r0`
- `b-2-r0`, provides `a=0.9`

If a user requests package `a`, `b` will be selected instead of `a` as it provides `a` (at version `0.9`) but has a higher package version (`2`).  Instead, `a` should be selected as it provides `a` at version `1`.

### Additional contract requirements

When multiple packages can satisfy a requested package name, compare candidates using the version each offers for that name. A package that provides the requested name offers the version declared for that name in its provides entry, while a package with the requested name offers its own package version. A provider with a higher offered version may therefore be selected even when its own package version is lower than the direct package's version.
