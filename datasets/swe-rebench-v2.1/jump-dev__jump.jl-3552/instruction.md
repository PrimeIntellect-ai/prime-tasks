Make `_DoNotConvertSet` Public
We need this for DisjunctiveProgramming. We need to intercept the `add_constraint` call be dispatching on our expression type along with the set (`_DoNotConvertSet`), but this is not public. Sorry I failed to bring this up in #3530.

### Additional contract requirements

The type is made public under the name `SkipModelConvertScalarSetWrapper`. It is exported by JuMP, so it is accessible as `SkipModelConvertScalarSetWrapper` after `using JuMP` and as `JuMP.SkipModelConvertScalarSetWrapper`.

`SkipModelConvertScalarSetWrapper(set::MOI.AbstractScalarSet)` constructs an immutable wrapper that exposes the provided set through a field named `set`, preserving the concrete type and value of the argument. The wrapper is a subtype of `MOI.AbstractScalarSet`.

Wrapping a set in `SkipModelConvertScalarSetWrapper` prevents JuMP from promoting the set to the model's value type when the constraint is added, so the wrapped set is passed to the solver unchanged. In particular, for a `ScalarConstraint` whose set is a `SkipModelConvertScalarSetWrapper`, `moi_set` returns the inner set (the original `MOI.AbstractScalarSet` supplied by the user).
