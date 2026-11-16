`Colorbar` fails on all zeros heatmap
mwe:
```julia
using GLMakie

main() = begin
  xs = LinRange(0, 20, 10)
  ys = LinRange(0, 15, 10)
  zs = zeros(length(xs), length(ys))

  fig = Figure()

  ax, hm = heatmap(fig[1, 1], xs, ys, zs)
  Colorbar(fig[1, 2], hm)

  display(fig)
  return
end

main()
```

Use case: fluid flow simulations, where arrays are initialized with all zeros.

<details>
  <summary>Fails with</summary>

```julia
ERROR: ArgumentError: range step cannot be zero
Stacktrace:
  [1] (::Colon)(start::Float32, step::Float32, stop::Float32)
    @ Base ./twiceprecision.jl:387
  [2] get_minor_tickvalues(i::IntervalsBetween, scale::Function, tickvalues::Vector{Float32}, vmin::Float32, vmax::Float32)
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/lineaxis.jl:609
  [3] (::Makie.MakieLayout.var"#194#225"{Observable{Vector{Float32}}, Observable{Any}, Attributes})(tickvalues::Vector{Float32}, minorticks::IntervalsBetween)
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/lineaxis.jl:238
  [4] (::Observables.OnUpdate{Makie.MakieLayout.var"#194#225"{Observable{Vector{Float32}}, Observable{Any}, Attributes}, Tuple{Observable{Vector{Float32}}, Observable{Any}}})(#unused#::Vector{Float32})
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:334
  [5] #invokelatest#2
    @ ./essentials.jl:708 [inlined]
  [6] invokelatest
    @ ./essentials.jl:706 [inlined]
  [7] notify
    @ [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:88 [inlined]
  [8] setindex!(observable::Observable{Vector{Float32}}, val::Vector{Float64})
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:248
  [9] (::Makie.MakieLayout.var"#190#221"{Observable{Vector{AbstractString}}, Observable{Vector{Point{2, Float32}}}, Observable{Vector{Float32}}, Observable{Tuple{Float32, Tuple{Float32, Float32}, Bool}}, Observable{Any}, Attributes})(tickvalues_labels_unfiltered::Tuple{Vector{Float64}, Vector{String}}, reversed::Bool)
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/lineaxis.jl:213
 [10] (::Observables.OnUpdate{Makie.MakieLayout.var"#190#221"{Observable{Vector{AbstractString}}, Observable{Vector{Point{2, Float32}}}, Observable{Vector{Float32}}, Observable{Tuple{Float32, Tuple{Float32, Float32}, Bool}}, Observable{Any}, Attributes}, Tuple{Observable{Tuple{Vector{Float64}, Vector{String}}}, Observable{Any}}})(#unused#::Tuple{Vector{Float64}, Vector{String}})
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:334
 [11] #invokelatest#2
    @ ./essentials.jl:708 [inlined]
 [12] invokelatest
    @ ./essentials.jl:706 [inlined]
 [13] notify
    @ [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:88 [inlined]
 [14] setindex!(observable::Observable{Tuple{Vector{Float64}, Vector{String}}}, val::Tuple{Vector{Float64}, Vector{String}})
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:248
 [15] (::Observables.MapUpdater{Makie.MakieLayout.var"#189#220", Tuple{Vector{Float64}, Vector{String}}})(::Tuple{Float32, Tuple{Float32, Float32}, Bool}, ::Vararg{Any, N} where N)
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:372
 [16] (::Observables.OnUpdate{Observables.MapUpdater{Makie.MakieLayout.var"#189#220", Tuple{Vector{Float64}, Vector{String}}}, Tuple{Observable{Tuple{Float32, Tuple{Float32, Float32}, Bool}}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}}})(#unused#::Tuple{Float32, Float32})
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:334
 [17] #invokelatest#2
    @ ./essentials.jl:708 [inlined]
 [18] invokelatest
    @ ./essentials.jl:706 [inlined]
 [19] notify
    @ [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:88 [inlined]
 [20] setindex!(observable::Observable{Any}, val::Tuple{Float32, Float32})
    @ Observables [...]/.julia/packages/Observables/OFj0u/src/Observables.jl:248
 [21] Makie.MakieLayout.LineAxis(parent::Scene; kwargs::Base.Iterators.Pairs{Symbol, Any, NTuple{35, Symbol}, NamedTuple{(:endpoints, :flipped, :limits, :ticklabelalign, :label, :labelpadding, :labelvisible, :labelsize, :labelcolor, :labelfont, :ticklabelfont, :ticks, :tickformat, :ticklabelsize, :ticklabelsvisible, :ticksize, :ticksvisible, :ticklabelpad, :tickalign, :ticklabelrotation, :tickwidth, :tickcolor, :spinewidth, :ticklabelspace, :ticklabelcolor, :spinecolor, :spinevisible, :flip_vertical_label, :minorticksvisible, :minortickalign, :minorticksize, :minortickwidth, :minortickcolor, :minorticks, :scale), Tuple{Observable{Tuple{Point{2, Float32}, Point{2, Float32}}}, Observable{Any}, Observable{Tuple{Float32, Float32}}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Symbol, Bool, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}, Observable{Any}}}})
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/lineaxis.jl:371
 [22] layoutable(::Type{Colorbar}, fig_or_scene::Figure; bbox::Nothing, kwargs::Base.Iterators.Pairs{Symbol, Observable{Any}, NTuple{4, Symbol}, NamedTuple{(:colormap, :limits, :highclip, :lowclip), NTuple{4, Observable{Any}}}})
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables/colorbar.jl:327
 [23] layoutable(::Type{Colorbar}, fig_or_scene::Figure, heatmap::Heatmap{Tuple{Vector{Float32}, Vector{Float32}, Matrix{Float32}}}; kwargs::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables/colorbar.jl:25
 [24] layoutable
    @ [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables/colorbar.jl:19 [inlined]
 [25] #_layoutable#11
    @ [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables.jl:69 [inlined]
 [26] _layoutable
    @ [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables.jl:69 [inlined]
 [27] _layoutable(T::Type{Colorbar}, gp::GridPosition, args::Heatmap{Tuple{Vector{Float32}, Vector{Float32}, Matrix{Float32}}}; kwargs::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables.jl:64
 [28] _layoutable(T::Type{Colorbar}, gp::GridPosition, args::Heatmap{Tuple{Vector{Float32}, Vector{Float32}, Matrix{Float32}}})
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables.jl:60
 [29] Colorbar(::GridPosition, ::Vararg{Any, N} where N; kwargs::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Makie.MakieLayout [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables.jl:49
 [30] Layoutable
    @ [...]/.julia/packages/Makie/vwpRo/src/makielayout/layoutables.jl:49 [inlined]
 [31] main()
    @ Main [...]/hm.jl:11
 [32] top-level scope
    @ [...]/.julia/config/startup.jl:210 [inlined]
 [33] top-level scope
    @ ./REPL[1]:0
 [34] eval
    @ :0 [inlined]
 [35] eval_user_input(ast::Any, backend::REPL.REPLBackend)
    @ REPL :139
 [36] repl_backend_loop(backend::REPL.REPLBackend)
    @ REPL :0
 [37] start_repl_backend(backend::REPL.REPLBackend, consumer::Any)
    @ REPL :0
 [38] run_repl(repl::REPL.AbstractREPL, consumer::Any; backend_on_current_task::Bool)
    @ REPL :0
 [39] run_repl(repl::REPL.AbstractREPL, consumer::Any)
    @ REPL :0
 [40] (::Base.var"#876#878"{Bool, Bool, Bool})(REPL::Module)
    @ Base ./client.jl:386
 [41] #invokelatest#2
    @ ./essentials.jl:708 [inlined]
 [42] invokelatest
    @ ./essentials.jl:706 [inlined]
 [43] run_main_repl(interactive::Bool, quiet::Bool, banner::Bool, history_file::Bool, color_set::Bool)
    @ Base ./client.jl:371
 [44] top-level scope
    @ none:21
```
</details>

### Additional contract requirements

- For an all-zeros heatmap, `hm.attributes[:colorrange][]` and the associated `Colorbar`'s `limits[]` must both be `(-.5, .5)`.
