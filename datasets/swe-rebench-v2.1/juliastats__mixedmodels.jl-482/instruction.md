Offset for Poisson models
Hi,

I might be missing something, but there doesn't seem to be any way to provide per-observation constant offsets for the `GeneralizedLinearMixedModel`?

The `fit` function supports an argument `offset`, but it doesn't appear to do anything. (Fitting with and without setting this gives the same result).

In the `GLM.jl` package the `fit` function for `GeneralizedLinearModel` has an `offset` argument that works.

How can I add an offset to a Poisson GLMM in MixedModels.jl?

Best,
/Valentine
