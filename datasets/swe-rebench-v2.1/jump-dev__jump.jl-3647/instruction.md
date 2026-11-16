@variable macro fails to resolve variables in 1.18.0
Here's a MWE:

```
using JuMP

m = Model()
x = (lower_bound=5.0,)
@variable(m, set = MOI.GreaterThan(x.lower_bound))
```

With JuMP 1.18.0, this fails with the error

```
ERROR: UndefVarError: `x` not defined
Stacktrace:
 [1] macro expansion
   @ ~/.julia/packages/JuMP/9tYtW/src/macros/@variable.jl:313 [inlined]
 [2] macro expansion
   @ ~/.julia/packages/JuMP/9tYtW/src/macros.jl:375 [inlined]
 [3] top-level scope
   @ ~/julia-envs/jump-bug/minrepro.jl:6
```

In JuMP 1.17 and below, there is no error.
