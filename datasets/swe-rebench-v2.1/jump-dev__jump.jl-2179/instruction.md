Creating empty SparseAxisArray not possible
I know this is a weird thing to complain about, but before JuMP 20.1 I used to be able to do this:
```julia
m = Model()
@variable(m, v[i=[], j=[]; j <= 2])
```
Now I get the following error:
```julia
ERROR: MethodError: no method matching JuMP.Containers.SparseAxisArray(::Dict{Any,Any})
Closest candidates are:
  JuMP.Containers.SparseAxisArray(::Dict{K<:Tuple{Vararg{Any,N}},T}) where {T, N, K<:Tuple{Vararg{Any,N}}} at /home/u0128861/.julia/packages/JuMP/CZ8vV/src/Containers/SparseAxisArray.jl:38
Stacktrace:
 [1] container(::Function, ::JuMP.Containers.NestedIterator{Tuple{getfield(Main, Symbol("##282#286")),getfield(Main, Symbol("##283#287"))},getfield(Main, Symbol("##284#288"))}, ::Type{JuMP.Containers.SparseAxisArray}) at /home/u0128861/.julia/packages/JuMP/CZ8vV/src/Containers/container.jl:94
 [2] container(::Function, ::JuMP.Containers.NestedIterator{Tuple{getfield(Main, Symbol("##282#286")),getfield(Main, Symbol("##283#287"))},getfield(Main, Symbol("##284#288"))}) at /home/u0128861/.julia/packages/JuMP/CZ8vV/src/Containers/container.jl:65
 [3] top-level scope at /home/u0128861/.julia/packages/JuMP/CZ8vV/src/macros.jl:79
```

This is obviously a trivial / silly complaint - the only reason I mention it is because it's useful for me to be able to make empty variables and expressions. I have a very general form of an energy system optimisation problem, and if for example some units (e.g. storage) don't exist then the form of my equations was still valid given JuMP's previous behaviour. I could of course just adapt my code to do something more sensible if it realises it's trying to make an empty sparse variable (e.g. return an array of zeros).
