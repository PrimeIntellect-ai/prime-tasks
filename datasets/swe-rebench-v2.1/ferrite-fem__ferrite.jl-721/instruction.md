Rename `Ferrite.value` and `Ferrite.derivative`
We now have
https://github.com/Ferrite-FEM/Ferrite.jl/blob/84e9aefd1cafc54d6aefd4587cecbf0e555d20f6/src/interpolations.jl#L65
and
https://github.com/Ferrite-FEM/Ferrite.jl/blob/84e9aefd1cafc54d6aefd4587cecbf0e555d20f6/src/interpolations.jl#L76
for computing the value and derivate of shape functions in the reference domain. These are not great names. We could (re)use `shape_value` and `shape_gradient` which is already used for `CellValues`, but in that case it is not in the reference domain, and would also "leak" these internal methods.

I don't have any good ideas,  hence the issue, but perhaps `reference_shape_value` and `reference_shape_gradient`.

### Additional contract requirements

Use `shape_value(ip::Interpolation, ξ::Vec, i::Int)` to evaluate the `i`th interpolation shape function at reference point `ξ`, and `shape_gradient(ip::Interpolation, ξ::Vec, i::Int)` to evaluate its gradient with respect to the reference coordinates. These names and argument order are the canonical replacement API and preserve the corresponding valid-input evaluation results of the old methods.

Keep `Ferrite.value` and `Ferrite.derivative` callable as deprecated compatibility aliases for their established interpolation-evaluation forms, including `Ferrite.value(ip, ξ)`, `Ferrite.value(ip, i, ξ)`, and `Ferrite.derivative(ip, ξ)`; they must produce the corresponding replacement API results.
