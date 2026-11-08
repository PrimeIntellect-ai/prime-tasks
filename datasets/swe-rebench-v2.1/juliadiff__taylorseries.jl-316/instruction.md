Cannot use more than 65 variables with TaylorN
Was just doing some work on my machine with TaylorN (OS X 10.10.5, julia-0.5; TaylorSeries v0.4.0), and then I came across some unexpected behaviour:
```julia
julia> using TaylorSeries
julia> δv = set_variables("δ", order=1, numvars=65);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 𝒪(‖x‖²) #this is OK
julia> δv = set_variables("δ", order=1, numvars=66);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₂ + 𝒪(‖x‖²) #the subscript on the δ should be 1 instead of 2
julia> δv = set_variables("δ", order=1, numvars=70);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₆ + 𝒪(‖x‖²) #the subscript on the δ should be 1 instead of 6
julia> δv = set_variables("δ", order=1, numvars=5);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 𝒪(‖x‖²) #this is OK
julia> δv = set_variables("δ", order=1, numvars=65);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 𝒪(‖x‖²) #this is OK
```

There seems to be a problem with `TaylorN` when `order==1` and `numvars>65`...

If I use `order=2` instead of `order=1`, everything works fine (this is the workaround I'm using):
```julia
julia> δv = set_variables("δ", order=2, numvars=65);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 1.0 δ₁² + 𝒪(‖x‖³) #OK
julia> δv = set_variables("δ", order=2, numvars=66);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 1.0 δ₁² + 𝒪(‖x‖³) #OK
julia> δv = set_variables("δ", order=2, numvars=70);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 1.0 δ₁² + 𝒪(‖x‖³) #OK
julia> δv = set_variables("δ", order=2, numvars=5);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 1.0 δ₁² + 𝒪(‖x‖³) #OK
julia> δv = set_variables("δ", order=2, numvars=65);
julia> (1+δv[1])^2
 1.0 + 2.0 δ₁ + 1.0 δ₁² + 𝒪(‖x‖³) #OK
```

After testing in JuliaBox (julia-0.5, TaylorSeries v0.4.0) the results are the same...

### Additional contract requirements

- With `order=1` and `numvars > 65`, `set_variables("δ", order=1, numvars=66)` must
  succeed (it must not raise an error), and the rendered output of `(1 + δv[1])^2`
  must display the first variable as `δ₁` — the subscript must be `1`, not `2`.
