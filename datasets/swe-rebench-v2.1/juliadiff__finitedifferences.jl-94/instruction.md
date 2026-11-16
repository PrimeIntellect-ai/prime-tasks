jvp returns incorrect tangent for 2-arg normalize
For `y=norm(x[, p])`, if `p` is not provided, `jvp` produces the correct tangent vector (with the same shape as `y`), but if `p` is provided, it returns a scalar.

```julia
julia> x, Δx = [1.0, 2.0, 3.0], [0.3, 0.2, 0.1];

julia> p, Δp = 2.0, 0.5;

julia> normalize(x)
3-element Array{Float64,1}:
 0.2672612419124244
 0.5345224838248488
 0.8017837257372732

julia> jvp(central_fdm(5, 1), normalize, (x, Δx)) # 1-arg looks good
3-element Array{Float64,1}:
  0.061088283865706784
  0.015272070966444149
 -0.0305441419328158

julia> normalize(x, p)
3-element Array{Float64,1}:
 0.2672612419124244
 0.5345224838248488
 0.8017837257372732

julia> jvp(central_fdm(5, 1), normalize, (x, Δx), (p, Δp)) # um, what?
0.08883239652055
```

### Additional contract requirements

For a `jvp` call with multiple primal/tangent argument pairs, when the function returns a vector, the returned tangent must also be a vector with the same shape as that function output; it must contain the directional derivative contributions from all argument pairs.
