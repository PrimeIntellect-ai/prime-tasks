inconsistent return order for `inverselink`
The function `inverselink` has different return orders:

For any `LinkFn <: Link01` the order is : `(μ, omμ, dμdη)` but for all others,  the order is `μ,  dμdη, omμ`, this is easily seen in the following calls:


Any link that is a subtype of `Link01`:
https://github.com/JuliaStats/GLM.jl/blob/705052e9aba6fe180d8f97d9c57fdaf038091e78/src/glmfit.jl#L184


for negative binomial:
https://github.com/JuliaStats/GLM.jl/blob/705052e9aba6fe180d8f97d9c57fdaf038091e78/src/glmfit.jl#L201


for all other (note there is an implicit third return that is not caught):
https://github.com/JuliaStats/GLM.jl/blob/705052e9aba6fe180d8f97d9c57fdaf038091e78/src/glmfit.jl#L111


The order for `Link01` links is contrary to the documentation:
```
"""
    GLM.inverselink(L::Link, η::Real)

Return a 3-tuple of the inverse link, the derivative of the inverse link, and when appropriate, the variance function `μ*(1 - μ)`.

The variance function is returned as NaN unless the range of μ is (0, 1)

...
"""
```
