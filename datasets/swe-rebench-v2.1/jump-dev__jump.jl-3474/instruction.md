Consider changing x^1 to return x
We currently have these methods:
https://github.com/jump-dev/JuMP.jl/blob/8a856bb677fdc1ec1e9a40a8a41e64089f7b6437/src/operators.jl#L201-L232

https://github.com/jump-dev/JuMP.jl/pull/3106 will make them somewhat more general by supporting `3`+ exponents. In doing so, it makes the return type unstable.

Once merged, we should consider changing `x^0` to return `one(T)` and `x^1` to return `x`.

See also https://github.com/jump-dev/JuMP.jl/pull/3106/files#r1295483658

### Additional contract requirements

For an integer exponent applied to a JuMP variable reference or affine expression, exponent zero returns `one(T)` for the underlying numeric type, and exponent one returns the original value.
