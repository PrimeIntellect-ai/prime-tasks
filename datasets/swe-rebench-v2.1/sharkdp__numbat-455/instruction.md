Typed holes
It would be great to support typed holes (see e.g. https://downloads.haskell.org/~ghc/7.10.1/docs/html/users_guide/typed-holes.html), so we could write something like
```rs
let x: Scalar = electron_charge^2 / (? ℏ c)
```
and the type checker would tell us that `?` is a typed hole of dimension `ElectricPermittivity`.

This should hopefully be easy to support once we have full type inference (see #29).

### Additional contract requirements

- A typed hole (`?`) encountered during type checking is reported as a `TypeCheckError::TypedHoleInStatement` error. The error carries, in order: the source span where the typed hole appears, a human-readable representation of the inferred type of the hole, and a statement string containing the hole.


- For the expressions `a + ?`, `c + a × ?`, `let x: B = c / ?`, and `let x: C = ?(a, b)`, report the inferred type strings exactly as `A`, `B`, `A`, and `Fn[(A, B) -> A × B]`, respectively.
