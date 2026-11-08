scalarize dropping metadata on latest v4 and v5 releases
```julia
using ModelingToolkit
@variables tv v(tv)[1:2] [input = true]
(Symbolics.unwrap(v)).metadata
```
gives
```
Base.ImmutableDict{DataType, Any} with 3 entries:
  VariableInput  => true
  VariableSource => (:variables, :v)
  ArrayShapeCtx  => (1:2,)
```
while
```julia
vs = Symbolics.scalarize(v)
vsw = Symbolics.unwrap.(vs)
vsw[1].metadata
```
is `nothing`.
