Wrong error when trying to set axis elements in `hist!` call
Per a discussion on Slack, I'm seeing:

```
f = Figure()
ax1 = Axis(f[1, 1])
hist!(ax1, rand(100), axis = (xlabel = "value", ylabel = "occurences"))

setting axis for scene via plot attribute not supported anymore

Stacktrace:
  [1] error(s::String)
    @ Base .\error.jl:33
  [2] plot!(scene::Scene, P::Type{Combined{Makie.hist, Tuple{Vector{Float64}}}}, attributes::Attributes, input::Tuple{Observable{Vector{Float64}}}, args::Observable{Tuple{Vector{Float64}}})
    @ Makie C:\Users\ngudat\.julia\packages\Makie\fEZv2\src\interfaces.jl:399
  [3] plot!(scene::Scene, P::Type{Combined{Makie.hist}}, attributes::Attributes, args::Vector{Float64}; kw_attributes::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Makie C:\Users\ngudat\.julia\packages\Makie\fEZv2\src\interfaces.jl:320
  [4] plot!
    @ C:\Users\ngudat\.julia\packages\Makie\fEZv2\src\interfaces.jl:288 [inlined]
  [5] plot!(la::Axis, P::Type{Combined{Makie.hist}}, attributes::Attributes, args::Vector{Float64}; kw_attributes::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
    @ Makie.MakieLayout C:\Users\ngudat\.julia\packages\Makie\fEZv2\src\makielayout\blocks\axis.jl:723
  [6] plot!
    @ C:\Users\ngudat\.julia\packages\Makie\fEZv2\src\makielayout\blocks\axis.jl:718 [inlined]
  [7] #plot!#379
    @ C:\Users\ngudat\.julia\packages\Makie\fEZv2\src\makielayout\blocks\axis.jl:735 [inlined]
  [8] hist!(::Axis, ::Vararg{Any}; attributes::Base.Pairs{Symbol, NamedTuple{(:xlabel, :ylabel), Tuple{String, String}}, Tuple{Symbol}, NamedTuple{(:axis,), Tuple{NamedTuple{(:xlabel, :ylabel), Tuple{String, String}}}}})
    @ Makie C:\Users\ngudat\.julia\packages\MakieCore\oBlaS\src\recipes.jl:37
  [9] top-level scope
    @ In[137]:3
 [10] eval
    @ .\boot.jl:373 [inlined]
 [11] include_string(mapexpr::typeof(REPL.softscope), mod::Module, code::String, filename::String)
    @ Base .\loading.jl:1196
```

This is on CairoMakie 0.8.3, Julia 1.7.2, Win10

### Additional contract requirements

When `hist!` is called with an explicit axis and an `axis=(...)` keyword, reject the call with an informative `ArgumentError` identifying the unsupported `axis` keyword. It must not fall through to the misleading scene-level error reported above.
