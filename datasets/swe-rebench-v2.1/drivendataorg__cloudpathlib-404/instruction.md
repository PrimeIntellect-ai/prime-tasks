Support file: ?
It's sympathic to use cloudpathlib with url `file:`.

### Additional contract requirements

`AnyPath` must accept `file:` URIs and return the corresponding local `pathlib.Path`:

- `AnyPath("file:/foo/bar")` and `AnyPath("file:///foo/bar")` both return `Path("/foo/bar")`.
- A `file:` URI produced by `Path.as_uri()` for an absolute path must round-trip back to that
  same absolute path, i.e. `AnyPath(p.absolute().resolve().as_uri()) == p.absolute().resolve()`.
