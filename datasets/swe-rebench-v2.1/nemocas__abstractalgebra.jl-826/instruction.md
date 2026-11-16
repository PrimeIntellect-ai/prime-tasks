tail for Poly and trailing_coefficient for MPoly?
We currently have tail for MPoly (well, if the PR gets merged we will) and trailing_coefficient for Poly.

Do we want these to work for all polynomial types, i.e. tail for Poly and trailing_coefficient for MPoly?

I don't see much of a use for tail for Poly. I'm not sure how important the latter is either.

Let me know if you want them or not. They are easy to implement.

### Additional contract requirements

- Provide `trailing_coefficient` for multivariate polynomials (`MPoly`), consistent with its behavior for univariate polynomials (`Poly`). For the zero polynomial, return zero from its coefficient ring.
