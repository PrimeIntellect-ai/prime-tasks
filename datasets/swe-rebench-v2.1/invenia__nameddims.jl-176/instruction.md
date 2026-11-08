Broadcasting assignment `.=` is broken for `NamedDimsArray`s
Compare dense arrays and `NamedDimsArrays`:

```julia
julia> rand(5, 2) .= rand(5, 1)
5×2 Matrix{Float64}:
 0.299664  0.299664
 0.981362  0.981362
 0.703687  0.703687
 0.591929  0.591929
 0.754977  0.754977

julia> NamedDimsArray{(:a, :b)}(rand(5, 2)) .= NamedDimsArray{(:a, :b)}(rand(5, 1))
ERROR: DimensionMismatch("destination axes (Base.OneTo(5), Base.OneTo(2)) are not compatible with source axes (Base.OneTo(5), Base.OneTo(1))")
Stacktrace:
 [1] throwdm(axdest::Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}, axsrc::Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}})
   @ Base.Broadcast ./broadcast.jl:1060
 [2] copyto!
   @ ./broadcast.jl:972 [inlined]
 [3] copyto!
   @ ./broadcast.jl:936 [inlined]
 [4] copyto!(dest::NamedDimsArray{(:a, :b), Float64, 2, Matrix{Float64}}, bc::Base.Broadcast.Broadcasted{NamedDims.NamedDimsStyle{Base.Broadcast.DefaultArrayStyle{2}}, Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}, typeof(identity), Tuple{NamedDimsArray{(:a, :b), Float64, 2, Matrix{Float64}}}})
   @ NamedDims ~/JuliaEnvs/PortfolioNets.jl/dev/NamedDims/src/broadcasting.jl:70
 [5] materialize!
   @ ./broadcast.jl:894 [inlined]
 [6] materialize!(dest::NamedDimsArray{(:a, :b), Float64, 2, Matrix{Float64}}, bc::Base.Broadcast.Broadcasted{NamedDims.NamedDimsStyle{Base.Broadcast.DefaultArrayStyle{2}}, Nothing, typeof(identity), Tuple{NamedDimsArray{(:a, :b), Float64, 2, Matrix{Float64}}}})
   @ Base.Broadcast ./broadcast.jl:891
 [7] top-level scope
   @ REPL[27]:1
```
