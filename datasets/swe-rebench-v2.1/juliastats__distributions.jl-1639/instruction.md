Weibull logpdf yields NaN at Inf
We currently have

```julia
julia> logpdf(Weibull(), Inf)
NaN
```

but we should get `-Inf`, of course. `pdf` is zero at `Inf`, as it should be:

```julia
julia> log(pdf(Weibull(), Inf))
-Inf
```
