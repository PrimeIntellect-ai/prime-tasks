argmax and argmin
Any reason these aren't implemented?

e.g.

```
X = NamedDimsArray{(:a, :b)}(rand(2,2))
@assert argmax(X; dims=:a) == argmax(X; dims=1)
```

### Additional contract requirements

- `Base.argmax(a::NamedDimsArray; dims=:, kwargs...)` and
  `Base.argmin(a::NamedDimsArray; dims=:, kwargs...)` are defined. `dims` may be a
  dimension name (a `Symbol`) or an integer position. The result is a
  `NamedDimsArray` whose dimension names equal `a`'s dimension names and whose
  shape equals `a`'s shape with the reduced dimension retained with length 1. Its
  entries are the indices of the maximum (respectively minimum) elements along the
  reduced dimension. Selecting a dimension by name gives the same result as
  selecting it by its integer position.
- `Base.findmax(a::NamedDimsArray; dims=:, kwargs...)` and
  `Base.findmin(a::NamedDimsArray; dims=:, kwargs...)` are defined. They return a
  tuple `(value, index)` in which both elements are `NamedDimsArray`s with the same
  shape and the same dimension names as `a` (the reduced dimension retained with
  length 1). `value` holds the maximum (respectively minimum) elements along the
  reduced dimension and `index` holds their indices.
- With the default `dims=:`, the reduction is over all elements and the result is
  the scalar index (for `argmax`/`argmin`) or the `(value, index)` tuple of scalars
  (for `findmax`/`findmin`), as in `Base`.
- Any additional keyword arguments are forwarded to the corresponding `Base`
  function.
