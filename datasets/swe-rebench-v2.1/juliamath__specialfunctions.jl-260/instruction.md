expint(n,x) is incorrect for negative integers n
The correct value of `expint(-4, 0.7)` is `142.68547122761425254403329916322251663998829971602071820534499366...`, but I'm getting:
```jl
julia> expint(-4, 0.7)
-6.413262697001885e15

julia> expint(-4 + 1e-13, 0.7 + 0im)
142.68547122758764 + 0.0im
```
cc @augustt198
