Incorrect summation with Hermitian matrices
This took me a while to track down!!!

```julia
julia> A = LinearAlgebra.Hermitian([1.0 2.0; 2.0 3.0] .+ [0 -4.0; 4.0 0.0] .* im)
2×2 LinearAlgebra.Hermitian{ComplexF64, Matrix{ComplexF64}}:
 1.0+0.0im  2.0-4.0im
 2.0+4.0im  3.0+0.0im

julia> model = Model();

julia> @variable(model, X[1:2, 1:2] in HermitianPSDCone())
2×2 Matrix{GenericAffExpr{ComplexF64, VariableRef}}:
 real(X[1,1])                                real(X[1,2]) + (0.0 + 1.0im) imag(X[1,2])
 real(X[1,2]) + (-0.0 - 1.0im) imag(X[1,2])  real(X[2,2])

julia> Y = LinearAlgebra.I - X
2×2 Matrix{GenericAffExpr{ComplexF64, VariableRef}}:
 (-1.0 - 0.0im) real(X[1,1]) + (1.0 - 0.0im)               (-1.0 - 0.0im) real(X[1,2]) + (-0.0 - 1.0im) imag(X[1,2])
 (-1.0 - 0.0im) real(X[1,2]) + (0.0 + 1.0im) imag(X[1,2])  (-1.0 - 0.0im) real(X[2,2]) + (1.0 - 0.0im)

julia> Z = LinearAlgebra.Hermitian(Y)
2×2 LinearAlgebra.Hermitian{GenericAffExpr{ComplexF64, VariableRef}, Matrix{GenericAffExpr{ComplexF64, VariableRef}}}:
 (-1.0 + 0.0im) real(X[1,1]) + (1.0 + 0.0im)                (-1.0 - 0.0im) real(X[1,2]) + (-0.0 - 1.0im) imag(X[1,2])
 (-1.0 + 0.0im) real(X[1,2]) + (-0.0 + 1.0im) imag(X[1,2])  (-1.0 + 0.0im) real(X[2,2]) + (1.0 + 0.0im)

julia> Y == Z
true

julia> real(LinearAlgebra.dot(A, X) + LinearAlgebra.dot(A, Y))
4

julia> real(LinearAlgebra.dot(A, X) + LinearAlgebra.dot(A, Z))
-16 imag(X[1,2]) + 4
```
