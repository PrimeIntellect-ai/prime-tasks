Add tests for analytics properties of copulas.
Copulas, as mathematical functions should fulfill some analytical properities:

- The copula is zero if one of the arguments is zero.
- The copula is equal to `u` if one argument is `u` and all others 1.

It would be nice to have one unittest for each property and copula on our test suite.
