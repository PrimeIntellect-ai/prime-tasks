Runic breaks unpacking of only the first element of a tuple
```julia
julia> Runic.format_string("x, = (1, 2, 3)")
"x = (1, 2, 3)"
```
That is, of course, not equivalent:
```julia
julia> x, = (1, 2, 3); x
1

julia> x = (1, 2, 3); x
(1, 2, 3)
```

### Additional contract requirements

- Formatting `a, b, = z` must produce `a, b, = z`.
