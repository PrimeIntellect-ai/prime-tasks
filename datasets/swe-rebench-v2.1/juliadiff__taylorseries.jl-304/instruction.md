Matrix element type for `A*A'`
I run into the following issue, when calculating `A*A'` for a matrix `A` with element type of `TaylorN`. The resulting matrix has elements of type `Any`. I would have expected to get elements of type `TaylorN` back, or is this the wanted/expected behavior?

```julia
(ts) pkg> st
      Status `....ts\Project.toml`
  [6aa5eb33] TaylorSeries v0.12.1

julia> using TaylorSeries

julia> x, y = set_variables("x y", order=2);

julia> A = [1.0 + x 0.1; 0.1 1.0 + y]
2×2 Matrix{TaylorN{Float64}}:
  1.0 + 1.0 x + 𝒪(‖x‖³)            0.1 + 𝒪(‖x‖¹)
          0.1 + 𝒪(‖x‖¹)    1.0 + 1.0 y + 𝒪(‖x‖³)

julia> A'
2×2 adjoint(::Matrix{TaylorN{Float64}}) with eltype TaylorN:
  1.0 + 1.0 x + 𝒪(‖x‖³)            0.1 + 𝒪(‖x‖¹)
          0.1 + 𝒪(‖x‖¹)    1.0 + 1.0 y + 𝒪(‖x‖³)

julia> A*A'
2×2 Matrix{Any}:
  1.01 + 2.0 x + 1.0 x² + 𝒪(‖x‖³)      0.2 + 0.1 x + 0.1 y + 𝒪(‖x‖³)
    0.2 + 0.1 x + 0.1 y + 𝒪(‖x‖³)    1.01 + 2.0 y + 1.0 y² + 𝒪(‖x‖³)

julia> versioninfo()
Julia Version 1.7.2
Commit bf53498635 (2022-02-06 15:21 UTC)
Platform Info:
  OS: Windows (x86_64-w64-mingw32)
  CPU: Intel(R) Core(TM) i7-8665U CPU @ 1.90GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-12.0.1 (ORCJIT, skylake)
Environment:
  JULIA_EDITOR = code
  JULIA_NUM_THREADS = 4
```

### Additional contract requirements

- For a matrix `A` whose elements are `TaylorN`, `A * A'` must return a matrix whose element type is a subtype of `TaylorN`, rather than `Any`.
