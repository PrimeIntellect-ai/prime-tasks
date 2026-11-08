Add string macro to define `KnotVector{Int}`
The following macro is not useful for most people but is useful for debugging and writing tests.
```julia
julia> using BasicBSpline

julia> macro knotvector_str(s)
           [HIDDEN]
       end
@knotvector_str (macro with 1 method)

julia> knotvector"1111"
KnotVector([1, 2, 3, 4])

julia> k1 = knotvector" 1 2  4 5"
KnotVector([2, 4, 4, 7, 7, 7, 7, 9, 9, 9, 9, 9])

julia> k2 = knotvector" 1 21 5 5"
KnotVector([2, 4, 4, 5, 7, 7, 7, 7, 7, 9, 9, 9, 9, 9])

julia> k3 = knotvector" 1 21 5 3"
KnotVector([2, 4, 4, 5, 7, 7, 7, 7, 7, 9, 9, 9])

julia> k1 ⊆ k2
true

julia> k1 ⊆ k3
false

```

### Additional contract requirements

- Provide `@knotvector_str(s::String)` and the `knotvector"..."` syntax; both produce a `KnotVector{Int}`.
- For each digit from `1` through `9` in the input, use its 1-based character position in the original string as a knot value, repeated as many times as the digit's numeric value. Other characters contribute no knot values but still count toward character positions.
