xcube server to verify valid cubes
**Is your feature request related to a problem? Please describe.**

xcube server must verify that configured cubes are valid, so that problems such as #103 are easier to understand address.

**Describe the solution you'd like**

[HIDDEN]

### Additional contract requirements

- `assert_cube` is a public function in module `xcube.api.verify` and is also importable as `xcube.api.assert_cube`. Its signature is `assert_cube(dataset: xr.Dataset, name: str = None) -> xr.Dataset`.
- When `dataset` is a valid data cube, `assert_cube` returns the supplied dataset unchanged.
- When `dataset` is not a valid data cube, `assert_cube` raises a `ValueError`. The message is a multiline report that begins with a statement that the dataset is not a valid data cube, followed by one line per detected problem, each prefixed with `- ` and separated by `;\n`, and terminated with a final `.`.
- The optional `name` argument is an identifier (for example a file name or level name) that is included in the error message so that the offending dataset can be identified.
- For a dataset whose `lat_bnds` and `lon_bnds` coordinates have dimensions `("time", "lat", "bnds")` and `("time", "lon", "bnds")`, shapes `(5, 180, 2)` and `(5, 360, 2)`, and whose `lon_bnds` dtype is `float16`, `assert_cube` raises `ValueError` with exactly this message:

```text
Dataset is not a valid data cube, because:
- bounds coordinate variable 'lat_bnds' must have dimensions ('lat', <bounds_dim>);
- shape of bounds coordinate variable 'lat_bnds' must be (180, 2) but was (5, 180, 2);
- bounds coordinate variable 'lon_bnds' must have dimensions ('lon', <bounds_dim>);
- shape of bounds coordinate variable 'lon_bnds' must be (360, 2) but was (5, 360, 2);
- type of bounds coordinate variable 'lon_bnds' must be dtype('float64') but was dtype('float16').
```
- For every configured dataset the server opens, it must ensure the resulting dataset is a valid data cube; invalid cubes must be rejected.
