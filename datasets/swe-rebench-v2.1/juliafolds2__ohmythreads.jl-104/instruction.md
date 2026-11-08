Empty collections in `tmap`
For `tmap` (and thus also `tcollect`) we currently have
```julia
julia> tmap(sin, 11:10)
ERROR: ArgumentError: You must either indicate the desired number of chunks (n) or the target size of a chunk (size).
Stacktrace:
  [1] missing_input_err()
    @ ChunkSplitters ~/.julia/packages/ChunkSplitters/R5lnx/src/ChunkSplitters.jl:118
  [2] getchunk(itr::UnitRange{Int64}, ichunk::Int64; n::Int64, size::Int64, split::Symbol)
    @ ChunkSplitters ~/.julia/packages/ChunkSplitters/R5lnx/src/ChunkSplitters.jl:274
  [3] getchunk
    @ ~/.julia/packages/ChunkSplitters/R5lnx/src/ChunkSplitters.jl:273 [inlined]
  [4] getchunk
    @ ~/.julia/packages/ChunkSplitters/R5lnx/src/ChunkSplitters.jl:293 [inlined]
  [5] iterate
    @ ~/.julia/packages/ChunkSplitters/R5lnx/src/ChunkSplitters.jl:142 [inlined]
  [6] iterate
    @ ~/.julia/packages/ChunkSplitters/R5lnx/src/ChunkSplitters.jl:141 [inlined]
  [7] copyto!(dest::Vector{StepRange{Int64, Int64}}, src::ChunkSplitters.Chunk{UnitRange{Int64}, ChunkSplitters.FixedCount})
    @ Base ~/.julia/juliaup/julia-1.10.2+0.aarch64.apple.darwin14/share/julia/base/abstractarray.jl:943
  [8] _collect
    @ ./array.jl:765 [inlined]
  [9] collect
    @ ./array.jl:759 [inlined]
 [10] _tmap(::DynamicScheduler{OhMyThreads.Schedulers.FixedCount}, ::Function, ::UnitRange{Int64})
    @ OhMyThreads.Implementation ~/repos/OhMyThreads.jl/src/implementation.jl:385
 [11] #tmap#81
    @ ~/repos/OhMyThreads.jl/src/implementation.jl:307 [inlined]
 [12] tmap(::Function, ::UnitRange{Int64})
    @ OhMyThreads.Implementation ~/repos/OhMyThreads.jl/src/implementation.jl:282
 [13] top-level scope
    @ REPL[91]:1
```

For comparison:
```julia
julia> map(sin, 11:10)
Float64[]

julia> map(x->im*x, 11:10)
Complex{Int64}[]

julia> map(x->im*x, 11.0:10.0)
ComplexF64[]
```

This is similar to #86 (`tforeach`) which led me to (https://github.com/JuliaFolds2/OhMyThreads.jl/pull/88) handle empty collections for `tmapreduce` (and thus also `tforeach`) explicitly (throw error if no `init` is supplied). I tried to align with the serial `mapreduce` / `foreach` behavior which, I think, is also what we should aim for here.
