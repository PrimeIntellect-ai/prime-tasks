`convert` extended but not imported from Base
This package defines `convert` without importing `Base.convert`, is that intended?

https://github.com/JuliaLinearAlgebra/GenericLinearAlgebra.jl/blob/10b5265b75e123f236ee50b03c845c642462c30e/src/householder.jl#L145

When trying to use it, I also get an error
```julia
julia> GenericLinearAlgebra.convert(Matrix, h2.τ[1])
ERROR: DimensionMismatch:
Stacktrace:
 [1] lmul!(H::GenericLinearAlgebra.Householder{BigFloat, SubArray{BigFloat, 1, Matrix{BigFloat}, Tuple{UnitRange{Int64}, Int64}, true}}, A::Matrix{BigFloat})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/w5JSi/src/householder.jl:24
 [2] convert(#unused#::Type{Matrix}, H::GenericLinearAlgebra.Householder{BigFloat, SubArray{BigFloat, 1, Matrix{BigFloat}, Tuple{UnitRange{Int64}, Int64}, true}})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/w5JSi/src/householder.jl:145
 [3] top-level scope
   @ REPL[27]:1
```
