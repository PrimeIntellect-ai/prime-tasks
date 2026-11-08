\in not supported in constraint macro
This code:
```julia
m = Model()
@variables(m, x)
@constraint(m, ctr[i ∈ 1:2], x >= i)
```
Results in error due to `∈`

If we use `∈` inside `sum` it works fine.
