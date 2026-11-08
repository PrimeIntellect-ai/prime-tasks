`get_attribute` is ambiguous
Currently, it is not possible to read an attribute of type Symbol from an object.
```julia
# Let G be of any type with @attribute
set_attribute(G, :propertyname, :value)
get_attribute(G, :propertyname, :defaultvalue)
```
The last line fails with
```julia
MethodError: get_attribute(::typeof(G), ::Symbol, ::Symbol) is ambiguous. Candidates:
    get_attribute(f, G, attr::Symbol) in AbstractAlgebra at /home/lgoe/.julia/packages/AbstractAlgebra/FcxWh/src/Attributes.jl:190
    get_attribute(G, attr::Symbol, default) in AbstractAlgebra at /home/lgoe/.julia/packages/AbstractAlgebra/FcxWh/src/Attributes.jl:202
  [HIDDEN]
```

### Additional contract requirements

- `get_attribute` must read Symbol-valued attributes. When given a Symbol default, it must return the stored value if present or the supplied default if absent, without an ambiguity error.
