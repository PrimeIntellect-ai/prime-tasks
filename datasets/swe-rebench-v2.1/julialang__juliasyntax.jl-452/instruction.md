GreenNode equality and hashing mismatch
```julia-repl
julia> x = JuliaSyntax.parse(JuliaSyntax.GreenNode, "1 + 1")
     1:5      │[call]
     1:1      │  Integer                ✔
     2:2      │  Whitespace
     3:3      │  +                      ✔
     4:4      │  Whitespace
     5:5      │  Integer                ✔


julia> y = JuliaSyntax.parse(JuliaSyntax.GreenNode, "1 + 1")
     1:5      │[call]
     1:1      │  Integer                ✔
     2:2      │  Whitespace
     3:3      │  +                      ✔
     4:4      │  Whitespace
     5:5      │  Integer                ✔


julia> x == y
true

julia> hash(x) == hash(y)
false
```

This makes `Dict`s broken.

### Additional contract requirements

- `hash` on a `JuliaSyntax.GreenNode` returns a `UInt`.
- GreenNodes parsed from `f(x) = x + 2` and `f(x) = 2 + x` must hash differently.
- GreenNodes parsed from `f(x) = x + 2` and `f(x) = 2 + x` must compare unequal.
