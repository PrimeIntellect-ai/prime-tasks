Plotting into an existing axis throws on v0.20.0
- [x] are you running newest version (version from docs) ?
- [x] can you reproduce the bug with a fresh environment ? (`]activate --temp; add Makie`)
- [x] What platform + GPU are you on? **Ubuntu 22.0.4, Nvidia**

Hello, thank you for all the hard work on Makie! After updating to latest, plotting into an existing axis throws.

```
julia> using GLMakie

julia> let
           fig = Figure()
           ax = Axis(fig[1, 1])
           plot!(ax, [10, 15, 20])
       end
ERROR: No recipe for plot
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:35
 [2] plot!
   @ ~/.julia/packages/Makie/AyuSG/src/interfaces.jl:223 [inlined]
 [3] connect_plot!(parent::Scene, plot::Plot{MakieCore.plot, Tuple{Vector{Int64}}})
   @ Makie ~/.julia/packages/Makie/AyuSG/src/interfaces.jl:251
 [4] plot!
   @ ~/.julia/packages/Makie/AyuSG/src/interfaces.jl:256 [inlined]
 [5] plot!(ax::Axis, plot::Plot{MakieCore.plot, Tuple{Vector{Int64}}})
   @ Makie ~/.julia/packages/Makie/AyuSG/src/figureplotting.jl:284
 [6] _create_plot!(::Function, ::Dict{Symbol, Any}, ::Axis, ::Vector{Int64})
   @ Makie ~/.julia/packages/Makie/AyuSG/src/figureplotting.jl:255
 [7] #plot!#11
   @ ~/.julia/packages/MakieCore/qQoPY/src/recipes.jl:39 [inlined]
 [8] plot!(::Axis, ::Vector{Int64})
   @ MakieCore ~/.julia/packages/MakieCore/qQoPY/src/recipes.jl:39
 [9] top-level scope
   @ REPL[4]:4
```
