Wrong inheritence of `MatrixView`
Consider the following:
```julia
julia> A = matrix(QQ, [1 2 3;4 5 6])
[1   2   3]
[4   5   6]

julia> v = view(A, :, 1)
2-element Nemo.MatrixView{QQMatrix, QQField}:
 1
 4

julia> eltype(v)
QQField

julia> supertypes(typeof(v))
(Nemo.MatrixView{QQMatrix, QQField}, AbstractVector{QQField}, Any)

julia> collect(v)
ERROR: MethodError: Cannot `convert` an object of type QQFieldElem to an object of type QQField

Closest candidates are:
  convert(::Type{T}, ::T) where T
   @ Base Base.jl:84

Stacktrace:
 [1] setindex!(A::Vector{QQField}, x::QQFieldElem, i1::Int64)
   @ Base ./array.jl:1021
 [2] copyto_unaliased!
   @ ./abstractarray.jl:1094 [inlined]
 [3] copyto!(dest::Vector{QQField}, src::Nemo.MatrixView{QQMatrix, QQField})
   @ Base ./abstractarray.jl:1068
 [4] _collect_indices
   @ ./array.jl:777 [inlined]
 [5] collect(A::Nemo.MatrixView{QQMatrix, QQField})
   @ Base ./array.jl:761
 [6] top-level scope
   @ REPL[7]:1
```
The `eltype` should be `QQFieldElem`, the correct supertypes would be `AbstractVector{QQFieldElem}`, and `collect` should work.
