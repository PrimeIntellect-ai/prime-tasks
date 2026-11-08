Uniform{Float32} pdf and cdf return inconsistent types
When passing a `Float64` to `pdf` or `logpdf`, for `Uniform{Float32}`, the result is a `Float32`, but for `cdf` and `logcdf`, the result is `Float64`:

```julia
julia> using Distributions

julia> d = Uniform(0f0, 1f0)
Uniform{Float32}(a=0.0f0, b=1.0f0)

julia> pdf(d, 1.0)
1.0f0

julia> logpdf(d, 1.0)
-0.0f0

julia> cdf(d, 1.0)
1.0

julia> logcdf(d, 1.0)
0.0
```

### Additional contract requirements

- For a `Uniform{T}` distribution and an input of type `S`, where `T` and `S` are each `Int`, `Float32`, or `Float64`, `pdf`, `logpdf`, `cdf`, `logcdf`, `ccdf`, and `logccdf` must return a value of type `float(promote_type(T, S))`, and that return type must be inferable.
