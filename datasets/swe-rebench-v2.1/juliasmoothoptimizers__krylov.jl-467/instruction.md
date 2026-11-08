NaN with GPMR on certain systems
[bug gpmr.zip](https://github.com/JuliaSmoothOptimizers/Krylov.jl/files/7677986/bug.gpmr.zip)

Hi, I have an issue with GPMR when solving some systems (I provided one in the above zip file with the code to read it):

```julia
using SparseArrays, LinearAlgebra, Krylov, DelimitedFiles, MatrixMarket
read_path = raw"C:\Users\Geoffroy Leconte\Documents\doctorat\code\bugs\bug gpmr"
A = MatrixMarket.mmread(string(read_path, "/A.mtx"))
E = readdlm(string(read_path, "/E.rhs"), Float64)[:]
δ = readdlm(string(read_path, "/delta.rhs"), Float64)[:][1]
ξ1 = readdlm(string(read_path, "/xi1.rhs"), Float64)[:]
ξ2 = readdlm(string(read_path, "/xi2.rhs"), Float64)[:]

(x, y, stats) = gpmr(A', A, ξ1, ξ2,
                      C = inv(Diagonal(sqrt.(E))), E = inv(Diagonal(sqrt.(E))),
                      D = (1.0 / sqrt(δ)) .* I,  F = (1.0 / sqrt(δ)) .* I, λ = -1.0)
```
This leads to `NaN`. I don't know if it is supposed to fail on such a system but if it is, it would be convenient to have something that terminates the algorithm and returns an error.

Since this is a saddle-point system I can solve it with TRIMR or TRICG (and it works):
```julia
(x, y, stats) = tricg(A', ξ1, ξ2, M = inv(Diagonal(E)), N = (1.0 / δ) .* I, flip=true)
```

### Additional contract requirements

When GPMR encounters an orthogonalization breakdown, it must not return non-finite solution values. It may report failure by throwing an exception; if it returns normally for a solvable system, the returned solution must satisfy the system to the requested tolerance. For an inconsistent system, a normal return must identify the inconsistency, while throwing an exception is also an acceptable report of failure.
