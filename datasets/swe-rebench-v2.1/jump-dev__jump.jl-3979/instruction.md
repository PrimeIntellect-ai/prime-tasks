cache option for set_optimizer
`Model` and `set_optimizer` have a keyword argument to specify if a bridge layer needs to be added.
It is also sometimes desirable to force a cache between the bridge layer and the solver.
This cache argument is supported by `MOI.instantiate` but there is no way to specify it from `Model` and `set_optimizer`.
The use case I faced today was using `print_active_bridges` in https://github.com/blegat/LowRankOpt.jl/pull/24
The issue was that SDPLR supports the incremental building of the model but not any getters so these were failing:
https://github.com/jump-dev/MathOptInterface.jl/blob/3c19dec53088441774a12cb9ee55c32d0f65844e/src/Bridges/debug.jl#L544-L546
