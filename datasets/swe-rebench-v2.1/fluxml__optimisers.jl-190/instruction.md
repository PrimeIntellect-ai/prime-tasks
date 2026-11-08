Adam optimizer can produce NaNs with Float16 due to small epsilon
Dear All,

I have found a bug in Adam's optimiser when used with Float16.
An MWE woud look like this
```julia
using Optimisers

x = Float16[0.579, -0.729, 0.5493]
δx = Float16[-0.001497, 0.0001875, -0.013176]

os = Optimisers.setup(Optimisers.Adam(Float16(1e-4)), x);
os, x = Optimisers.update(os, x, δx)
```
where after update `x = Float16[Inf, -Inf, 0.5493]`. This happens with `Optimisers 0.3.2`. I believe the problem is caused on this line https://github.com/FluxML/Optimisers.jl/blob/1908a1cd599f656b15304a9722328bf9b2eed360/src/rules.jl#L221 because default `ϵ` is in Float64 and it is too small.
When I initialize Adam with different epsilon as `Optimisers.Adam(1e-4, (0.9, 0.999),  eps(Float16))`, it works well.
[HIDDEN]

I can prepare a pull-request with this test.

### Additional contract requirements

- For the displayed `x` and `δx`, using `os = Optimisers.setup(Adam(1e-4), x)`, after `os, x = Optimisers.update(os, x, δx)`, require `x ≈ Float16[1.835, -0.886, 0.5493]` with `rtol=1e-3`.
