Add `ktypeof` support for view arrays
Hello,

I'm trying to calculate the eigenvalues of a sparse matrix with the arnoldi method written in this package, taking advantage of the `bicgstab` function to do the shift-inverse algorithm, and finding the lowest eigenvalues.
I'm already able to do it with a modified version of the KrylovKit package, which has the `eigsolve` function, which supports any abstract linear map. And with this implementation I'm able to speed up the calculation by a factor 10 or more against the Arpack package, which is very useful for calculating large sparse matrices, also for GPUs.

With this package, I went through an error when calculating the Hessenberg matrix through the `arnoldi` function.

```julia
using LinearAlgebra
using SparseArrays
using IncompleteLU
using Krylov
using LinearOperators

N = 500
A = sprand(ComplexF64, N, N, 3 / N)
A *= A'
A = triu(A, 1) + sprand(ComplexF64, N, N, 0.5 / N)

μ = 1
A = A - μ * I # SHIFT
P = ilu(A, τ=0.001)

b = rand(ComplexF64, size(A, 1))

solver = BicgstabSolver(N, N, typeof(b))

# INVERSE MAP
Map = LinearOperator(eltype(b), N, N, false, false, (y, x) -> copyto!(y, bicgstab!(solver, A, x, M = P, ldiv = true).x))

arnoldi(Map, b, 20)
```

```julia
ERROR: MethodError: no method matching ktypeof(::Matrix{ComplexF64})
Closest candidates are:
  ktypeof(::S) where S<:(DenseVector) at ~/.julia/packages/Krylov/0uvPR/src/krylov_utils.jl:203
  ktypeof(::S) where S<:SparseVector at ~/.julia/packages/Krylov/0uvPR/src/krylov_utils.jl:207
  ktypeof(::S) where S<:(AbstractSparseVector) at ~/.julia/packages/Krylov/0uvPR/src/krylov_utils.jl:212
  ...
Stacktrace:
 [1] ktypeof(v::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true})
   @ Krylov ~/.julia/packages/Krylov/0uvPR/src/krylov_utils.jl:222
 [2] bicgstab!(solver::BicgstabSolver{Float64, ComplexF64, Vector{ComplexF64}}, A::SparseMatrixCSC{ComplexF64, Int64}, b::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}; c::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, M::IncompleteLU.ILUFactorization{ComplexF64, Int64}, N::UniformScaling{Bool}, atol::Float64, rtol::Float64, itmax::Int64, verbose::Int64, history::Bool, ldiv::Bool, callback::Krylov.var"#232#234")
   @ Krylov ~/.julia/packages/Krylov/0uvPR/src/bicgstab.jl:118
 [3] (::var"#13#14")(y::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, x::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true})
   @ Main ./Untitled-1:195
 [4] prod3!(res::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, prod!::var"#13#14", v::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, α::ComplexF64, β::ComplexF64, Mv5::Vector{ComplexF64})
   @ LinearOperators ~/.julia/packages/LinearOperators/QYye7/src/operations.jl:12
 [5] mul!(res::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, op::LinearOperator{ComplexF64, Int64, var"#13#14", Nothing, Nothing, Vector{ComplexF64}}, v::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, α::ComplexF64, β::ComplexF64)
   @ LinearOperators ~/.julia/packages/LinearOperators/QYye7/src/operations.jl:31
 [6] mul!(res::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true}, op::LinearOperator{ComplexF64, Int64, var"#13#14", Nothing, Nothing, Vector{ComplexF64}}, v::SubArray{ComplexF64, 1, Matrix{ComplexF64}, Tuple{Base.Slice{Base.OneTo{Int64}}, Int64}, true})
   @ LinearOperators ~/.julia/packages/LinearOperators/QYye7/src/operations.jl:36
 [7] arnoldi(A::LinearOperator{ComplexF64, Int64, var"#13#14", Nothing, Nothing, Vector{ComplexF64}}, b::Vector{ComplexF64}, k::Int64)
   @ Krylov ~/.julia/packages/Krylov/0uvPR/src/krylov_processes.jl:210
 [8] top-level scope
   @ Untitled-1:197
```

I think that the problem is related to the use of the `view` function

https://github.com/JuliaSmoothOptimizers/Krylov.jl/blob/c88e3e2a341cc7de3d2a19bbaa5d8dc12ea72652/src/krylov_processes.jl#L203-L210

Indeed, the multiplication `mul!(q, A, vᵢ)` calls the bicgstab solver function

https://github.com/JuliaSmoothOptimizers/Krylov.jl/blob/a42db8e18a251af99df08ca1c1a748909c9132cc/src/krylov_solvers.jl#L876-L880

but here `b` is a SubArray whose parent is a Matrix. And that is the error.
