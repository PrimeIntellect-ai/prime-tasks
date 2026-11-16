Implement tail for polynomials
This should return everything but the leading_term.

For multivariates, implementation should be independent of representation. Singular can likely do this faster than Nemo, but we'd still need to make a copy in our model. Perhaps there should be a "view/sub" version which allows access to the tail without a copy.
