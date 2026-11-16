Feature request: Support options without default values
Nice repo! I am trying to create an application, in which it is unsafe to make either the argument `name` a positional argument, or a keyword argument having a default value.

```julia
@cast function generate_smallgraph(problem::String;
    name::String,
    weights::Union{Nothing,Vector{Float64}}=nothing,
    datafolder::String="data", prefix::String="")
    graph = SmallGraphConfig(name)
    config = GraphProblemConfig(; problem, graph, weights, openvertices=Int[])
    foldername(datafolder, config; create=true, prefix)
end
```

The error message is
```julia
shell> julia --project project/run.jl generate-smallgraph IndependentSet --name=petersen
ERROR: LoadError: options should have default values or make it a positional argument
```

I wish it can be supported!

### Additional contract requirements

Keyword parameters without defaults are supported as named CLI options. They are required: omitting one must fail, while supplying one must pass its value to the command using the parameter's declared type.
