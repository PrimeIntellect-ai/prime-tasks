Compatibility with SparseArrays
Hey, thanks for all the recent work on IntervalArithmetic!

It seems that common functionality for SparseArrays are still broken on 0.22.7 (despite #604):
```julia
julia> using IntervalArithmetic

julia> using SparseArrays

julia> x = [1.0 0; 0 0]
2×2 Matrix{Float64}:
 1.0  0.0
 0.0  0.0

julia> spx = sparse(x)
2×2 SparseMatrixCSC{Float64, Int64} with 1 stored entry:
 1.0   ⋅
  ⋅    ⋅

julia> spix = interval.(spx)
2×2 SparseMatrixCSC{Interval{Float64}, Int64} with 1 stored entry:
 [1.0, 1.0]_com        ⋅
       ⋅               ⋅

julia> spx .= zero(eltype(spx))
2×2 SparseMatrixCSC{Float64, Int64} with 1 stored entry:
 0.0   ⋅
  ⋅    ⋅

julia> spix .= zero(eltype(spix))
ERROR: ArgumentError: `==` is purposely not supported for intervals. See instead `isequal_interval`
Stacktrace:
 [1] ==(::Interval{Float64}, ::Interval{Float64})
   @ IntervalArithmetic ~/.julia/packages/IntervalArithmetic/7FL3g/src/intervals/real_interface.jl:83
 [2] fill!(A::SparseMatrixCSC{Interval{Float64}, Int64}, x::Interval{Float64})
   @ SparseArrays ~/.julia/juliaup/julia-1.10.0+0.x64.linux.gnu/share/julia/stdlib/v1.10/SparseArrays/src/sparsevector.jl:2303
 [3] copyto!
   @ Base.Broadcast ./broadcast.jl:964 [inlined]
 [4] materialize!
   @ Base.Broadcast ./broadcast.jl:914 [inlined]
 [5] materialize!(dest::SparseMatrixCSC{Interval{Float64}, Int64}, bc::Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{0}, Nothing, typeof(identity), Tuple{Interval{Float64}}})
   @ Base.Broadcast ./broadcast.jl:911
 [6] top-level scope
   @ REPL[24]:1
```

which can be traced to this line:
https://github.com/JuliaSparse/SparseArrays.jl/blob/4cc31f23619cfe4c2bcded16e71b7ec5cef974f9/src/sparsevector.jl#L2381

Looking at the comments of the file this is intentional to support `-0.0` which `iszero` but is not equal to `0.0`.

### Additional contract requirements

Broadcast-assigning zero to a sparse matrix whose element type is an interval must complete successfully and leave zero intervals at all matrix positions. Equality between two proper (non-thin) intervals must remain unsupported. Sparse scalar assignment must distinguish negative zero from positive zero: assigning `-0.0` to a sparse array must preserve it as a stored negative zero, while assigning positive zero leaves the entry implicit.
