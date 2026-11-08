Writing to NL file fails
This used to work, so something must have changed:
```Julia
julia> model = Model()
A JuMP Model
Feasibility problem with:
Variables: 0
Model mode: AUTOMATIC
CachingOptimizer state: NO_OPTIMIZER
Solver name: No optimizer attached.

julia> @variable(model, x >= 0)
x

julia> @objective(model, Min, 2x + 1)
2 x + 1

julia> write_to_file(model, "test.nl")
ERROR: Model MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.FileFormats.NL.Model} does not support copy_to.
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:33
 [2] default_copy_to(dest::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.FileFormats.NL.Model}, src::MathOptInterface.Utilities.CachingOptimizer{MathOptInterface.AbstractOptimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}})
   @ MathOptInterface.Utilities ~/.julia/packages/MathOptInterface/FHFUH/src/Utilities/copy.jl:454
 [3] copy_to(dest::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.FileFormats.NL.Model}, src::MathOptInterface.Utilities.CachingOptimizer{MathOptInterface.AbstractOptimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}}; kwargs::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
   @ MathOptInterface.Bridges ~/.julia/packages/MathOptInterface/FHFUH/src/Bridges/bridge_optimizer.jl:421
 [4] copy_to(dest::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.FileFormats.NL.Model}, src::MathOptInterface.Utilities.CachingOptimizer{MathOptInterface.AbstractOptimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}})
   @ MathOptInterface.Bridges ~/.julia/packages/MathOptInterface/FHFUH/src/Bridges/bridge_optimizer.jl:421
 [5] copy_to(dest::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.FileFormats.NL.Model}, src::Model)
   @ JuMP ~/.julia/packages/JuMP/0STkJ/src/copy.jl:290
 [6] write_to_file(model::Model, filename::String; format::MathOptInterface.FileFormats.FileFormat)
   @ JuMP ~/.julia/packages/JuMP/0STkJ/src/file_formats.jl:27
 [7] write_to_file(model::Model, filename::String)
   @ JuMP ~/.julia/packages/JuMP/0STkJ/src/file_formats.jl:23
 [8] top-level scope
   @ REPL[13]:1
```

MOI reproducer
```Julia
using MathOptInterface
const MOI = MathOptInterface
src = MOI.Utilities.Model{Float64}()
x = MOI.add_variable(src)
MOI.add_constraint(src, x, MOI.GreaterThan(0.0))
dest = MOI.Bridges.full_bridge_optimizer(MOI.FileFormats.NL.Model(), Float64)
MOI.copy_to(dest, src)
```

### Additional contract requirements

- For an NL-format export of a model with objective `(1 - x)^2 + 100 * (y - x^2)^2` and constraints `x^2 + y^2 <= 100.0` and `x + y == 10`, the serialized text must contain the exact substring `n100`.
