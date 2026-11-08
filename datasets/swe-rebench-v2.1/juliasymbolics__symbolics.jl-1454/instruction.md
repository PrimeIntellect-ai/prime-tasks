`LoadError: MethodError: no method matching _sparse(::SymbolicUtils.BasicSymbolic{Any}, ::Int64)`
I tried the following code:
```
using Symbolics, IfElse

f(x) = Base.ifelse( # IfElse.ifelse doesn't work either
    x[1] <= 0,
    -x[1],
    x[1],
)
x0 = ones(1)
nvar = 1

@variables xs[1:nvar]
xsi = Symbolics.scalarize(xs)
fun = f(xsi)
S = Symbolics.hessian_sparsity(fun, xsi)
```
and got the following error
```
ERROR: LoadError: MethodError: no method matching _sparse(::SymbolicUtils.BasicSymbolic{Any}, ::Int64)
Closest candidates are:
  _sparse(::Number, ::Any) at .julia\packages\Symbolics\gy00O\src\linearity.jl:170
  _sparse(::Symbolics.TermCombination, ::Any) at .julia\packages\Symbolics\gy00O\src\linearity.jl:147
Stacktrace:
 [1] hessian_sparsity(expr::Num, vars::Vector{Num}; full::Bool)
   @ Symbolics .julia\packages\Symbolics\gy00O\src\diff.jl:679
 [2] hessian_sparsity(expr::Num, vars::Vector{Num})
   @ Symbolics .julia\packages\Symbolics\gy00O\src\diff.jl:671
```

It might be related to https://github.com/JuliaSymbolics/Symbolics.jl/issues/888 .
