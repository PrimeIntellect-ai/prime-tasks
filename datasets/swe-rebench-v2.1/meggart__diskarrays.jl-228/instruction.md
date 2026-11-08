Fix method ambiguities
```julia
(@v1.8) pkg> st
Status `~/.julia/environments/v1.8/Project.toml`
  [4c88cf16] Aqua v0.5.5
  [3c3547ce] DiskArrays v0.3.6

julia> using DiskArrays, Aqua

julia> Aqua.test_all(DiskArrays)
Skipping Base.active_repl
Skipping Base.active_repl_backend
Skipping Base.Filesystem.JL_O_RANDOM
Skipping Base.Filesystem.JL_O_SEQUENTIAL
Skipping Base.Filesystem.JL_O_SHORT_LIVED
Skipping Base.Filesystem.JL_O_TEMPORARY
13 ambiguities found
Ambiguity #1
copyto!(dest::AbstractMatrix, Rdest::CartesianIndices{2, R} where R<:Tuple{OrdinalRange{Int64, Int64}, OrdinalRange{Int64, Int64}}, src::SparseArrays.AbstractSparseMatrixCSC{T}, Rsrc::CartesianIndices{2, R} where R<:Tuple{OrdinalRange{Int64, Int64}, OrdinalRange{Int64, Int64}}) where T in SparseArrays at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/SparseArrays/src/sparsematrix.jl:481
copyto!(dest::DiskArrays.AbstractDiskArray, Rdest::CartesianIndices, src::AbstractArray, Rsrc::CartesianIndices) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:8

Possible fix, define
  copyto!(::DiskArrays.AbstractDiskArray{T, 2} where T, ::CartesianIndices{2, R} where R<:Tuple{OrdinalRange{Int64, Int64}, OrdinalRange{Int64, Int64}}, ::SparseArrays.AbstractSparseMatrixCSC{T}, ::CartesianIndices{2, R} where R<:Tuple{OrdinalRange{Int64, Int64}, OrdinalRange{Int64, Int64}}) where T

Ambiguity #2
reverse(a::DiskArrays.AbstractDiskArray, dims) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:23
reverse(A::AbstractVector, start::Integer) in Base at array.jl:1803

Possible fix, define
  reverse(::DiskArrays.AbstractDiskArray{T, 1} where T, ::Integer)

Ambiguity #3
copyto!(dest::AbstractArray, D::SuiteSparse.CHOLMOD.Dense) in SuiteSparse.CHOLMOD at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/SuiteSparse/src/cholmod.jl:830
copyto!(dest::DiskArrays.AbstractDiskArray, source::AbstractArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:5

Possible fix, define
  copyto!(::DiskArrays.AbstractDiskArray, ::SuiteSparse.CHOLMOD.Dense)

Ambiguity #4
copyto!(A::AbstractMatrix, B::SparseArrays.AbstractSparseMatrixCSC) in SparseArrays at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/SparseArrays/src/sparsematrix.jl:458
copyto!(dest::DiskArrays.AbstractDiskArray, source::AbstractArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:5

Possible fix, define
  copyto!(::DiskArrays.AbstractDiskArray{T, 2} where T, ::SparseArrays.AbstractSparseMatrixCSC)

Ambiguity #5
copyto!(dest::AbstractMatrix, src::LinearAlgebra.AbstractQ) in LinearAlgebra at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/LinearAlgebra/src/qr.jl:599
copyto!(dest::DiskArrays.AbstractDiskArray, source::AbstractArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:5

Possible fix, define
  copyto!(::DiskArrays.AbstractDiskArray{T, 2} where T, ::LinearAlgebra.AbstractQ)

Ambiguity #6
commonlength(::Tuple{}, b) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/diskarray.jl:154
commonlength(a, ::Tuple{}) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/diskarray.jl:155

Possible fix, define
  commonlength(::Tuple{}, ::Tuple{})

Ambiguity #7
_commonlength(a1, b1, ::Tuple{}, b) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/diskarray.jl:157
_commonlength(a1, b1, a, ::Tuple{}) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/diskarray.jl:158

Possible fix, define
  _commonlength(::Any, ::Any, ::Tuple{}, ::Tuple{})

Ambiguity #8
copyto!(dest::AbstractArray, source::DiskArrays.AbstractDiskArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:6
copyto!(dest::PermutedDimsArray, src::AbstractArray) in Base.PermutedDimsArrays at permuteddimsarray.jl:215

Possible fix, define
  copyto!(::PermutedDimsArray, ::DiskArrays.AbstractDiskArray)

Ambiguity #9
copyto!(dest::AbstractArray{T}, D::SuiteSparse.CHOLMOD.Dense{T}) where T<:Union{Float64, ComplexF64} in SuiteSparse.CHOLMOD at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/SuiteSparse/src/cholmod.jl:828
copyto!(dest::DiskArrays.AbstractDiskArray, source::AbstractArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:5

Possible fix, define
  copyto!(::DiskArrays.AbstractDiskArray{T}, ::SuiteSparse.CHOLMOD.Dense{T}) where T<:Union{Float64, ComplexF64}

Ambiguity #10
copyto!(A::SparseArrays.SparseVector, B::AbstractVector) in SparseArrays at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/SparseArrays/src/sparsevector.jl:501
copyto!(dest::AbstractArray, source::DiskArrays.AbstractDiskArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:6

Possible fix, define
  copyto!(::SparseArrays.SparseVector, ::DiskArrays.AbstractDiskArray{T, 1} where T)

Ambiguity #11
copyto!(dest::AbstractArray, source::DiskArrays.AbstractDiskArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:6
copyto!(dest::PermutedDimsArray{T, N}, src::AbstractArray{T, N}) where {T, N} in Base.PermutedDimsArrays at permuteddimsarray.jl:211

Possible fix, define
  copyto!(::PermutedDimsArray{T, N}, ::DiskArrays.AbstractDiskArray{T, N}) where {T, N}

Ambiguity #12
_reshape(parent::DiskArrays.AbstractDiskArray, dims::Tuple{Vararg{Int64, var"#164#N"}}) where var"#164#N" in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/reshape.jl:79
_reshape(v::AbstractVector, dims::Tuple{Int64}) in Base at reshapedarray.jl:168

Possible fix, define
  _reshape(::DiskArrays.AbstractDiskArray{T, 1} where T, ::Tuple{Int64})

Ambiguity #13
copyto!(dest::AbstractMatrix{T}, D::SuiteSparse.CHOLMOD.Dense{T}) where T<:Union{Float64, ComplexF64} in SuiteSparse.CHOLMOD at /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/SuiteSparse/src/cholmod.jl:829
copyto!(dest::DiskArrays.AbstractDiskArray, source::AbstractArray) in DiskArrays at /Users/yeesian/.julia/packages/DiskArrays/bcti2/src/array.jl:5

Possible fix, define
  copyto!(::DiskArrays.AbstractDiskArray{T, 2}, ::SuiteSparse.CHOLMOD.Dense{T}) where T<:Union{Float64, ComplexF64}

Method ambiguity: Test Failed at /Users/yeesian/.julia/packages/Aqua/HWLbM/src/ambiguities.jl:117
  Expression: success(pipeline(cmd; stdout = stdout, stderr = stderr))
Stacktrace:
 [1] macro expansion
   @ /Applications/Julia-1.8.app/Contents/Resources/julia/share/julia/stdlib/v1.8/Test/src/Test.jl:464 [inlined]
 [2] _test_ambiguities(packages::Vector{Base.PkgId}; color::Nothing, exclude::Vector{Any}, detect_ambiguities_options::Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
   @ Aqua ~/.julia/packages/Aqua/HWLbM/src/ambiguities.jl:117
Test Summary:    | Fail  Total  Time
Method ambiguity |    1      1  1.7s
ERROR: Some tests did not pass: 0 passed, 1 failed, 0 errored, 0 broken.

```

### Additional contract requirements

- The method ambiguities that must be resolved are those detected by `Aqua.test_ambiguities([DiskArrays, Base, Core])` on the Julia versions supported by the package (Julia 1.9 and later).
