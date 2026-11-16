`Adjoint{VariableRef} * NamedDimsArray` breaks
```julia
julia> using NamedDims

julia> using JuMP

julia> m = Model();

julia> x = rand(5);

julia> nda = NamedDimsArray{(:a,)}(x);

julia> z = @variable(m, [1:5]);

julia> z' * x # works
0.262369216144402 _[1] + 0.5685890754024013 _[2] + 0.20130403647700346 _[3] + 0.2260366062767406 _[4] + 0.6009129347889277 _[5]

julia> z' * nda # breaks
ERROR: MethodError: *(::LinearAlgebra.Adjoint{VariableRef, Vector{VariableRef}}, ::NamedDimsArray{(:a,), Float64, 1, Vector{Float64}}) is ambiguous. Candidates:
  *(u::Union{LinearAlgebra.Adjoint{T, var"#s859"}, LinearAlgebra.Transpose{T, var"#s859"}} where {T, var"#s859"<:(AbstractVector)}, v::AbstractVector) in LinearAlgebra at /Applications/Julia-1.7.app/Contents/Resources/julia/share/julia/stdlib/v1.7/LinearAlgebra/src/adjtrans.jl:293
  *(a::AbstractMatrix, b::NamedDimsArray{var"#s3", var"#s2", 1, A} where {var"#s3", var"#s2", A<:AbstractVector{var"#s2"}}) in NamedDims at /Users/mzgubic/.julia/packages/NamedDims/HvlfO/src/functions_math.jl:86
[HIDDEN]
Stacktrace:
 [1] top-level scope
   @ REPL[28]:1

julia> x' * z # works
0.262369216144402 _[1] + 0.5685890754024013 _[2] + 0.20130403647700346 _[3] + 0.2260366062767406 _[4] + 0.6009129347889277 _[5]

julia> nda' * z # works
0.262369216144402 _[1] + 0.5685890754024013 _[2] + 0.20130403647700346 _[3] + 0.2260366062767406 _[4] + 0.6009129347889277 _[5]
```

### Additional contract requirements

- Multiplication of the adjoint or transpose of any `AbstractVector` by a one-dimensional `NamedDimsArray` must work for arbitrary element types. The result must match the corresponding multiplication using the `NamedDimsArray`’s underlying ordinary vector.
