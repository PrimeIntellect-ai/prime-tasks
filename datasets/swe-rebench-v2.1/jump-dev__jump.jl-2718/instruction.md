Unhelpful error message for `@NLparameter`
The error message when you set keyword arguments is unhelpful:
```Julia
julia> model = Model();

julia> @NLparameter(model, p == 1, base_name = "x")
ERROR: LoadError: At REPL[7]:1: `@NLparameter(model, p == 1)`: Too many arguments.
Stacktrace:
 [1] error(::String, ::String)
   @ Base ./error.jl:42
 [2] _macro_error(macroname::Symbol, args::Tuple{Symbol, Expr}, source::LineNumberNode, str::String)
   @ JuMP ~/.julia/dev/JuMP/src/macros.jl:1365
 [3] (::JuMP.var"#_error#122"{LineNumberNode, Symbol, Expr})(str::String)
   @ JuMP ~/.julia/dev/JuMP/src/macros.jl:2114
 [4] var"@NLparameter"(__source__::LineNumberNode, __module__::Module, m::Any, ex::Any, extra::Vararg{Any, N} where N)
   @ JuMP ~/.julia/dev/JuMP/src/macros.jl:2118
in expression starting at REPL[7]:1
```

### Additional contract requirements

- `@NLparameter` accepts the optional `container` keyword to select the returned container type, using the same container names as JuMP's other container macros: `Array`, `DenseAxisArray` or `SparseAxisArray` (for example, `container = Array`). Unsupported keywords, such as `base_name`, must be rejected with an error message that makes clear the keyword argument is unsupported, rather than reporting only a generic argument-count error.
