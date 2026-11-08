Scalarize errors for inverses
Here is a MWE:
```julia
using Symbolics

@variables η[1:12, 1:12]

expr =  inv(η)
Symbolics.scalarize(expr[1,1])
```
results in
```julia
ERROR: MethodError: no method matching one(::Type{SymbolicUtils.Term{Real, Nothing}})
Closest candidates are:
  one(::Union{Type{T}, T}) where T<:AbstractString at ~/.asdf/installs/julia/1.7.3/share/julia/base/strings/basic.jl:262
  one(::Union{Type{P}, P}) where P<:Dates.Period at ~/.asdf/installs/julia/1.7.3/share/julia/stdlib/v1.7/Dates/src/periods.jl:54
  one(::AbstractAlgebra.MatrixElem{T}) where T<:Union{AbstractAlgebra.NCRingElem, AbstractAlgebra.RingElement} at ~/.julia/packages/AbstractAlgebra/9oioa/src/Matrix.jl:205
  ...
Stacktrace:
 [1] inv(A::Matrix{SymbolicUtils.Term{Real, Nothing}})
   @ LinearAlgebra ~/.asdf/installs/julia/1.7.3/share/julia/stdlib/v1.7/LinearAlgebra/src/dense.jl:869
 [2] scalarize_op(f::Function, arr::SymbolicUtils.Term{AbstractMatrix{Real}, Base.ImmutableDict{DataType, Any}}, idx::Tuple{Int64, Int64})
   @ Symbolics ~/.julia/packages/Symbolics/kG5bl/src/arrays.jl:629
 [3] scalarize(arr::SymbolicUtils.Term{AbstractMatrix{Real}, Base.ImmutableDict{DataType, Any}}, idx::Tuple{Int64, Int64})
   @ Symbolics ~/.julia/packages/Symbolics/kG5bl/src/arrays.jl:618
 [4] scalarize(arr::SymbolicUtils.Term{Real, Nothing})
   @ Symbolics ~/.julia/packages/Symbolics/kG5bl/src/arrays.jl:721
 [5] scalarize(arr::Num)
   @ Symbolics ~/.julia/packages/Symbolics/kG5bl/src/arrays.jl:723
 [6] top-level scope
   @ REPL[24]:1

````
