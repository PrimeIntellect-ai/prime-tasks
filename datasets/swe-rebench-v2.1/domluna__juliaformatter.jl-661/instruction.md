Avoid removal of semicolon in vertical concatenation
The following code

```julia
[
  a;
]
```

is currently formatted to

```julia
[
  a
]
```

which, for `a::AbstractVector` is no longer equivalent because the former is a "flattened" vector whereas the latter is a vector of vector.
