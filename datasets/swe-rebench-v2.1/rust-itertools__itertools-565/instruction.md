multizip equivalent for unzip
It would be nice to have something similar to `izip!`/`multizip` for `unzip`, e.g. `A, B, C, D, A, B, C, D, ...` -> `([A, A, A, [...], B, B, B, [...], [...])`

### Additional contract requirements

The iterator extension method for this operation is named `multiunzip()`.

Callers can select compatible collection types for the output columns; the operation is not limited to `Vec`.
