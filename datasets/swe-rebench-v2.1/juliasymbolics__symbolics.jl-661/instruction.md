`semilinear_form` & `semipolynomial_form` return nonlinear function as coefficient
link to PR #428

```
julia> using Symbolics

julia> @variables x
1-element Vector{Num}:
 x

julia> expr = x * cos(x) + x^2 * 3sin(x) + 4exp(x)
4exp(x) + x*cos(x) + 3(x^2)*sin(x)
```

For the above expression, I expected the entire expression to be returned as residual.

```
julia> A, c = semilinear_form([expr], [x])
(sparse([1], [1], Num[cos(x)], 1, 1), Num[4exp(x) + 3(x^2)*sin(x)])

julia> A
1×1 SparseArrays.SparseMatrixCSC{Num, Int64} with 1 stored entry:
 cos(x)

julia> c
1-element Vector{Num}:
 4exp(x) + 3(x^2)*sin(x)

julia> ds, nls = semipolynomial_form([expr], [x], Inf)
(Dict{Any, Any}[Dict(x => cos(x), x^2 => 3sin(x))], SymbolicUtils.Mul{Real, Int64, Dict{Any, Number}, Nothing}[4exp(x)])

julia> ds
1-element Vector{Dict{Any, Any}}:
 Dict(x => cos(x), x^2 => 3sin(x))

julia> nls
1-element Vector{SymbolicUtils.Mul{Real, Int64, Dict{Any, Number}, Nothing}}:
 4exp(x)
```

However, `cos(x)` and `3sin(x)` are treated as the coefficient for monomials `x` and `x^2`.

I am wondering if this is really the intended behavior.

@shashi

### Additional contract requirements

- For the same expression, `semipolynomial_form([expr], [x], Inf)` should return coefficient values that are all zero and the entire expression as its nonlinear residual.
