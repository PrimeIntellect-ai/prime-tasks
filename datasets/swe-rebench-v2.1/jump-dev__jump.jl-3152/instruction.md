DenseAxisArray with Symbol key does not support setting
Reported on discourse: https://discourse.julialang.org/t/denseaxisarray-not-working-as-expected-with-single-dimensional/91646

```julia
julia> D = Containers.DenseAxisArray(zeros(3), [:a, :b, :c])
1-dimensional DenseAxisArray{Float64,1,...} with index sets:
    Dimension 1, [:a, :b, :c]
And data, a 3-element Vector{Float64}:
 0.0
 0.0
 0.0

julia> E = Containers.DenseAxisArray(ones(3), [:a, :b, :c])
1-dimensional DenseAxisArray{Float64,1,...} with index sets:
    Dimension 1, [:a, :b, :c]
And data, a 3-element Vector{Float64}:
 1.0
 1.0
 1.0

julia> I = [:a, :b]
2-element Vector{Symbol}:
 :a
 :b

julia> D[I] = E[I]
ERROR: MethodError: no method matching Int64(::Symbol)
Closest candidates are:
  (::Type{T})(::AbstractChar) where T<:Union{AbstractChar, Number} at char.jl:50
  (::Type{T})(::BigInt) where T<:Union{Int128, Int16, Int32, Int64, Int8} at gmp.jl:356
  (::Type{T})(::Base.TwicePrecision) where T<:Number at twiceprecision.jl:243
  ...
Stacktrace:
 [1] (::Base.var"#105#106")(x::Vector{Symbol})
   @ Base ./abstractarray.jl:99
 [2] _tuple_any(::Base.var"#105#106", ::Bool, ::Vector{Symbol})
   @ Base ./tuple.jl:497
 [3] _tuple_any(f::Function, t::Tuple{Vector{Symbol}})
   @ Base ./tuple.jl:494
 [4] has_offset_axes(A::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}})
   @ Base ./abstractarray.jl:99
 [5] require_one_based_indexing(A::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}})
   @ Base ./abstractarray.jl:103
 [6] setindex!
   @ ./array.jl:851 [inlined]
 [7] setindex!(A::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, v::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, idx::Vector{Symbol})
   @ JuMP.Containers ~/.julia/packages/JuMP/puvTM/src/Containers/DenseAxisArray.jl:344
 [8] top-level scope
   @ REPL[13]:1

julia> D[I] = 0.0
ERROR: ArgumentError: indexed assignment with a single value to many locations is not supported; perhaps use broadcasting `.=` instead?
Stacktrace:
 [1] setindex_shape_check(::Float64, ::Int64)
   @ Base ./indices.jl:261
 [2] _unsafe_setindex!(#unused#::IndexLinear, A::Vector{Float64}, x::Float64, I::Vector{Int64})
   @ Base ./multidimensional.jl:902
 [3] _setindex!
   @ ./multidimensional.jl:893 [inlined]
 [4] setindex!
   @ ./abstractarray.jl:1267 [inlined]
 [5] setindex!(A::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, v::Float64, idx::Vector{Symbol})
   @ JuMP.Containers ~/.julia/packages/JuMP/puvTM/src/Containers/DenseAxisArray.jl:344
 [6] top-level scope
   @ REPL[14]:1

julia> D[I] .= 0.0
ERROR: MethodError: no method matching one(::Symbol)
Closest candidates are:
  one(::Union{Type{T}, T}) where T<:AbstractString at strings/basic.jl:262
  one(::Union{Type{P}, P}) where P<:Dates.Period at /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.6/Dates/src/periods.jl:54
  one(::LinearAlgebra.Tridiagonal{T, V} where V<:AbstractVector{T}) where T at /Users/julia/buildbot/worker/package_macos64/build/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/special.jl:307
  ...
Stacktrace:
  [1] isone(x::Symbol)
    @ Base ./number.jl:60
  [2] (::JuMP.Containers.var"#9#11"{Vector{Symbol}})(i::Int64)
    @ JuMP.Containers ~/.julia/packages/JuMP/puvTM/src/Containers/DenseAxisArray.jl:323
  [3] _any
    @ ./reduce.jl:876 [inlined]
  [4] #any#702
    @ ./reducedim.jl:883 [inlined]
  [5] any
    @ ./reducedim.jl:883 [inlined]
  [6] to_index(A::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, idx::Vector{Symbol})
    @ JuMP.Containers ~/.julia/packages/JuMP/puvTM/src/Containers/DenseAxisArray.jl:323
  [7] to_indices
    @ ./indices.jl:333 [inlined]
  [8] to_indices
    @ ./indices.jl:325 [inlined]
  [9] view
    @ ./subarray.jl:176 [inlined]
 [10] maybeview
    @ ./views.jl:133 [inlined]
 [11] dotview(::JuMP.Containers.DenseAxisArray{Float64, 1, Tuple{Vector{Symbol}}, Tuple{JuMP.Containers._AxisLookup{Dict{Symbol, Int64}}}}, ::Vector{Symbol})
    @ Base.Broadcast ./broadcast.jl:1212
 [12] top-level scope
    @ REPL[15]:1
```

### Additional contract requirements

- Broadcasting a scalar into a selected region of a symbol-indexed `DenseAxisArray` updates each selected location and leaves locations outside the selection unchanged.
