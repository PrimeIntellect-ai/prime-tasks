Add convenient method equivalent to`TempDir:new('foo')`
I want to remove the dependabot for https://github.com/advisories/GHSA-mc8h-8q98-g5hr and I miss the old `TempDir:new('foo')` call.

The available constructors have different semantics and the proposed solution is kinda verbose: [HIDDEN]

### Additional contract requirements

- Add a public associated function `TempDir::with_prefix<S: AsRef<OsStr>>(prefix: S) -> io::Result<TempDir>` that creates a temporary directory in the default temporary directory whose name starts with `prefix`.
- Add a public associated function `TempDir::with_prefix_in<S: AsRef<OsStr>, P: AsRef<Path>>(prefix: S, dir: P) -> io::Result<TempDir>` that creates a temporary directory inside `dir` whose name starts with `prefix`.
- A temporary directory returned by `TempDir::with_prefix` or `TempDir::with_prefix_in`, and everything inside it, is automatically removed when the returned value is dropped.
