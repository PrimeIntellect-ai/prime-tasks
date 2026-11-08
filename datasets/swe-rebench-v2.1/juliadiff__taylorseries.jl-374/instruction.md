Inconsistent behavior when saving `TaylorN`s with JLD2 v0.4
When saving a long `Vector{TaylorN{Float64}}` with JLD2 v0.4 (required minor version in `Project.toml`) I get inconsistent results:
```julia
v = set_variables(Float64, "dx"; order = 5, numvars = 6)
x = [exp(sum(rand(6) .* v)) for _ in 1:10_000]
begin
    for _ in 1:10
        jldsave("test.jld2"; x)
        y = JLD2.load("test.jld2", "x")
        println(count(x .!= y))
    end
end
# 3451, 1967, 965, 0, 0, 0, 2051, 0, 1663, 1305
```
But with JLD2 v0.5 (latest minor version), everything works:
```julia
# 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
```
¿@lbenet can you reproduce this?
