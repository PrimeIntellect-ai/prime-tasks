impl `Div<f32>`/`Div<f64>` for [`D`]`MatX`
The implementation should be almost the same as `Mul` implementation. Don't know why it's not implemented yet but that would be useful.

### Additional contract requirements

- Support scalar compound-assignment division for the matrix types covered by the request: `m /= s` must update each component to its previous value divided by `s`, for both `f32` and `f64` scalar types.
