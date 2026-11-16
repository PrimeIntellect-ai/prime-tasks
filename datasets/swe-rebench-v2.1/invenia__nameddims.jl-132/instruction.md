Ambiguity on 1.5: Adjoint{...,Vector} * NamedDimsArray{...,Vector}
Julia 1.5 seems to cause extra method ambiguities, for instance this:
```julia
julia> using NamedDims

julia> rand(3)' * NamedDimsArray(rand(3), :a)
ERROR: MethodError: *(::LinearAlgebra.Adjoint{Float64,Array{Float64,1}}, ::NamedDimsArray{(:a,),Float64,1,Array{Float64,1}}) is ambiguous. Candidates:
  *(u::LinearAlgebra.Adjoint{T,var"#s814"} where var"#s814"<:(AbstractArray{T,1} where T), v::AbstractArray{T,1}) where T<:Number in LinearAlgebra at /Applications/Julia-1.5.app/Contents/Resources/julia/share/julia/stdlib/v1.5/LinearAlgebra/src/adjtrans.jl:267
  *(a::LinearAlgebra.Adjoint{var"#s16",var"#s15"} where var"#s15"<:(AbstractArray{T,1} where T) where var"#s16", b::NamedDimsArray{L,T,1,var"#s17"} where var"#s17"<:AbstractArray{T,1}) where {L, T} in NamedDims at /Users/me/.julia/packages/NamedDims/p7e4G/src/functions_math.jl:48
[HIDDEN]
Stacktrace:
 [1] top-level scope at REPL[2]:1

julia> [ones(2,2), ones(2,2)]' * NamedDimsArray([ones(2,2), ones(2,2)], :a)
2×2 Array{Float64,2}:
 4.0  4.0
 4.0  4.0
```

xref https://github.com/mcabbott/AxisKeys.jl/issues/17

Edit: also here: https://github.com/JuliaCI/NanosoldierReports/blob/master/pkgeval/by_date/2020-05/09/logs/NamedDims/1.6.0-DEV-b828bbc426.log#L129

### Additional contract requirements

- Multiplying an adjoint numeric vector by a one-dimensional `NamedDimsArray` backed by a compatible vector must dispatch unambiguously and produce the same result as multiplying the corresponding unwrapped vectors.
