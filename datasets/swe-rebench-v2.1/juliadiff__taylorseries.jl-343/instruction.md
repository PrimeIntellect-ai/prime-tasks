Bug in Taylor1 constructor for mixtures
When modifying in-place a single coefficient of a `Taylor1{TaylorN{Float64}}`, the value is copied almost everywhere:
```julia
julia> using TaylorSeries

julia> set_variables("x", numvars=2, order=6)
2-element Vector{TaylorN{Float64}}:
  1.0 x₁ + 𝒪(‖x‖⁷)
  1.0 x₂ + 𝒪(‖x‖⁷)

julia> z0N = -1.333+get_variables()[1]
 - 1.333 + 1.0 x₁ + 𝒪(‖x‖⁷)

julia> z = Taylor1(z0N,5)
  - 1.333 + 1.0 x₁ + 𝒪(‖x‖⁷) + 𝒪(t⁶)

julia> z[5][1][1] = 5.0
5.0

julia> z
  - 1.333 + 1.0 x₁ + 𝒪(‖x‖⁷) + ( 5.0 x₁ + 𝒪(‖x‖⁷)) t + ( 5.0 x₁ + 𝒪(‖x‖⁷)) t² + ( 5.0 x₁ + 𝒪(‖x‖⁷)) t³ + ( 5.0 x₁ + 𝒪(‖x‖⁷)) t⁴ + ( 5.0 x₁ + 𝒪(‖x‖⁷)) t⁵ + 𝒪(t⁶)
```

The expected output is simply:
```julia
julia> z
  - 1.333 + 1.0 x₁ + 𝒪(‖x‖⁷) + ( 5.0 x₁ + 𝒪(‖x‖⁷)) t⁵ + 𝒪(t⁶)
```

Update: while writing this issue I found the culprit and will submit a PR soon!
