`hessian_sparsity` errors for functions with > 2 arguments
As expected, for known traceable functions with e.g. 3 arguments the sparsity pattern is inferred correctly:

```julia
julia> using Symbolics

julia> @variables x y z;

julia> f(x, y, z) = x * y^2 + z;

julia> Symbolics.hessian_sparsity(f(x, y, z), [x, y, z])
3×3 SparseArrays.SparseMatrixCSC{Bool, Int64} with 3 stored entries:
 ⋅  1  ⋅
 1  1  ⋅
 ⋅  ⋅  ⋅
```

However, for unknown functions with >= 3 arguments `hessian_sparsity` errors:

```julia
julia> g(x, y, z) = x * y^2 + z
g (generic function with 1 method)

julia> @register_symbolic g(x, y, z)

julia> Symbolics.hessian_sparsity(g(x, y, z), [x, y, z])
ERROR: MethodError: no method matching _sparse(::SymbolicUtils.BasicSymbolic{Any}, ::Int64)
The function `_sparse` exists, but no method is defined for this combination of argument types.

Closest candidates are:
  _sparse(::Symbolics.TermCombination, ::Any)
   @ Symbolics ~/.julia/packages/Symbolics/CjPtz/src/linearity.jl:131
  _sparse(::Number, ::Any)
   @ Symbolics ~/.julia/packages/Symbolics/CjPtz/src/linearity.jl:154
  _sparse(::Type{Tv}, ::Type{Ti}, ::Any) where {Tv, Ti}
   @ Symbolics ~/.julia/packages/Symbolics/CjPtz/src/linear_algebra.jl:379

Stacktrace:
 [1] hessian_sparsity(expr::Num, vars::Vector{Num}; full::Bool)
   @ Symbolics ~/.julia/packages/Symbolics/CjPtz/src/diff.jl:709
 [2] hessian_sparsity(expr::Num, vars::Vector{Num})
   @ Symbolics ~/.julia/packages/Symbolics/CjPtz/src/diff.jl:702
 [3] top-level scope
   @ REPL[16]:1
```

---

Compare this with what happens for functions with 2 arguments:

As expected, for known traceable functions the sparsity pattern is inferred correctly:

```julia
julia> f2(x, y) = x * y^2;

julia> Symbolics.hessian_sparsity(f2(x, y), [x, y])
2×2 SparseArrays.SparseMatrixCSC{Bool, Int64} with 3 stored entries:
 ⋅  1
 1  1
```

For unknown functions, the default fallback (non-sparse) is used (was added in #1384):

```julia
julia> g2(x, y) = x * y^2;

julia> @register_symbolic g2(x, y)

julia> Symbolics.hessian_sparsity(g2(x, y), [x, y])
2×2 SparseArrays.SparseMatrixCSC{Bool, Int64} with 4 stored entries:
 1  1
 1  1
```
