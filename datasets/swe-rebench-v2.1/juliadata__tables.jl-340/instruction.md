Type stability of `Tables.matrix(::NamedTuple)`
I'm descending some type instability issues in my package and realized that `Tables.matrix(::NamedTuple)` is not type stable. Would this be feasible to implement?

For example:

```julia
julia> using Tables

julia> X = (x=randn(32), y=randn(32));

julia> typeof(Tables.matrix(X))
Matrix{Float64} (alias for Array{Float64, 2})

julia> @code_warntype Tables.matrix(X)
MethodInstance for Tables.matrix(::@NamedTuple{x::Vector{Float64}, y::Vector{Float64}})
  from matrix(table; transpose) @ Tables ~/.julia/packages/Tables/AcRIE/src/matrix.jl:84
Arguments
  #self#::Core.Const(Tables.matrix)
  table::@NamedTuple{x::Vector{Float64}, y::Vector{Float64}}
Body::Matrix
1 ─ %1 = Tables.:(var"#matrix#85")(false, #self#, table)::Matrix
└──      return %1
```

So the type inference is not able to infer that this is a `Matrix{Float64}`, only that it is a `Matrix{Any}`, despite the method call being specialized to a NamedTuple with `Vector{Float64}` for columns.

Version info:

```
Julia Version 1.10.0-beta1
Commit 6616549950e (2023-07-25 17:43 UTC)
Platform Info:
  OS: macOS (arm64-apple-darwin22.4.0)
  CPU: 8 × Apple M1 Pro
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, apple-m1)
  Threads: 8 on 6 virtual cores
Environment:
  JULIA_FORMATTER_SO = /Users/mcranmer/julia_formatter.so
  JULIA_NUM_THREADS = auto
  JULIA_EDITOR = code
```
