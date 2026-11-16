CartesianIndex as keys in a DenseAxisArray
Reported on SO: https://stackoverflow.com/questions/70284721/julia-jump-how-to-use-variable-with-cartesianindex/70296103

There's some weird things that happen:
```Julia
julia> model = Model()
A JuMP Model
Feasibility problem with:
Variables: 0
Model mode: AUTOMATIC
CachingOptimizer state: NO_OPTIMIZER
Solver name: No optimizer attached.

julia> S = CartesianIndex.([2, 4])
2-element Vector{CartesianIndex{1}}:
 CartesianIndex(2,)
 CartesianIndex(4,)

julia> @variable(model, x[S])
1-dimensional DenseAxisArray{VariableRef,1,...} with index sets:
    Dimension 1, CartesianIndex{1}[CartesianIndex(2,), CartesianIndex(4,)]
And data, a 2-element Vector{VariableRef}:
 x[CartesianIndex(2,)]
 x[CartesianIndex(4,)]

julia> x[CartesianIndex(2,)]
x[CartesianIndex(4,)]

julia> x[CartesianIndex(1,)]
x[CartesianIndex(2,)]

julia> x[CartesianIndex(4,)]
ERROR: BoundsError: attempt to access 2-element Vector{VariableRef} at index [4]
Stacktrace:
 [1] getindex
   @ ./array.jl:801 [inlined]
 [2] getindex
   @ ./multidimensional.jl:637 [inlined]
 [3] getindex(A::JuMP.Containers.DenseAxisArray{VariableRef, 1, Tuple{Vector{CartesianIndex{1}}}, Tuple{JuMP.Containers._AxisLookup{Dict{CartesianIndex{1}, Int64}}}}, idx::CartesianIndex{1})
   @ JuMP.Containers ~/.julia/packages/JuMP/2IF9U/src/Containers/DenseAxisArray.jl:323
 [4] top-level scope
   @ REPL[42]:1
```

### Additional contract requirements

A `DenseAxisArray` cannot use an axis containing `CartesianIndex` keys; construction must reject such an axis, whether it is the first or a later dimension. The rejection does not require a particular exception type or message.

When an axis is a vector of tuples, each tuple is one key in that axis. Constructing a `DenseAxisArray` with such an axis must preserve the tuples as individual keys and allow lookup using a tuple key.
