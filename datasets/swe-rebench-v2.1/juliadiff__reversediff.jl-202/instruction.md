Problem with getindex for ReverseDiff.TrackedArray if Integer is a UInt16
Started getting this error after updating from 1.2.0 to 1.4.1:

MethodError: no method matching ReverseDiff.TrackedArray(::Float64, ::Float64, ::Array{ReverseDiff.AbstractInstruction,1})
Closest candidates are:
  ReverseDiff.TrackedArray(!Matched::AbstractArray{V,N}, !Matched::AbstractArray{D,N}, ::Array{ReverseDiff.AbstractInstruction,1}) where {V, D, N} at ~/.julia/packages/ReverseDiff/tCOFA/src/tracked.jl:86

Stacktrace:
 [1] getindex(::ReverseDiff.TrackedArray{Float64,Float64,1,Array{Float64,1},Array{Float64,1}}, ::UInt16) at ~/.julia/packages/ReverseDiff/tCOFA/src/tracked.jl:337

When the indexes are changed to Int64 no error is thrown.
