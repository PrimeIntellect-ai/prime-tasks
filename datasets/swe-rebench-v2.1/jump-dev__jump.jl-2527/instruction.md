Bool.(::DenseAxisArray) errors
I have been solving a problem with binary (`Bin`) variables.
To my annoyance, they come out as floating point values.
So I convert them by calling `Bool`.

I thought i could clean my code up by doing the convert at the same time as a did the `value`
`Bool.(value.(my_bin_array_var))`

But i got this error:
```
ERROR: MethodError: no method matching JuMP.Containers.DenseAxisArray(::BitArray{2}, ::Tuple{Tuple{Int64,Int64,Int64},Tuple{Symbol,Symbol,Symbol}}, ::Tuple{Dict{Int64,Int64},Dict{Symbol,Int64}})
```

Presumably this is because broadcasting `Bool` over a `Array` gives back a `BitArray`.
and `DenseAxisArray` is not prepared to handle that.

Here is a MWE without a solve in it::
```julia
julia> x = JuMP.Containers.DenseAxisArray([rand((0.0, 1.0)) for _ in 1:3, _ in 1:3], (1,2,3),(:a,:b, :c))
2-dimensional DenseAxisArray{Float64,2,...} with index sets:
    Dimension 1, (1, 2, 3)
    Dimension 2, (:a, :b, :c)
And data, a 3×3 Array{Float64,2}:
 1.0  0.0  0.0
 1.0  1.0  1.0
 1.0  0.0  0.0

julia> Bool.(x)
ERROR: MethodError: no method matching JuMP.Containers.DenseAxisArray(::BitArray{2}, ::Tuple{Tuple{Int64,Int64,Int64},Tuple
Symbol,Symbol,Symbol}}, ::Tuple{Dict{Int64,Int64},Dict{Symbol,Int64}})
Closest candidates are:
  JuMP.Containers.DenseAxisArray(::Array{T,N}, ::Ax, ::L) where {T, N, Ax, L<:Tuple{Vararg{Dict,N}}} at /Users/oxinabox/.ju
ia/packages/JuMP/YXK4e/src/Containers/DenseAxisArray.jl:13
  JuMP.Containers.DenseAxisArray(::Array{T,N}, ::Any...) where {T, N} at /Users/oxinabox/.julia/packages/JuMP/YXK4e/src/Con
ainers/DenseAxisArray.jl:53
Stacktrace:
 [1] broadcasted(::JuMP.Containers.DenseAxisArrayBroadcastStyle, ::Type{T} where T, ::JuMP.Containers.DenseAxisArray{Float6
,2,Tuple{Tuple{Int64,Int64,Int64},Tuple{Symbol,Symbol,Symbol}},Tuple{Dict{Int64,Int64},Dict{Symbol,Int64}}}) at /Users/oxin
box/.julia/packages/JuMP/YXK4e/src/Containers/DenseAxisArray.jl:253
 [2] broadcasted(::Type{T} where T, ::JuMP.Containers.DenseAxisArray{Float64,2,Tuple{Tuple{Int64,Int64,Int64},Tuple{Symbol,
ymbol,Symbol}},Tuple{Dict{Int64,Int64},Dict{Symbol,Int64}}}) at ./broadcast.jl:1232
 [3] top-level scope at REPL[10]:1
```
