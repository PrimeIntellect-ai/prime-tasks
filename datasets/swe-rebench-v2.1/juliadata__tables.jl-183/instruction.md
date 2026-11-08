Copying in matrix(table(A)) when A is a matrix
I was expecting that if `A` is a matrix and I do `t = table(A)` then `matrix(t)` just unwraps `A`, ie no copying.  But evidently this is not the case:

```julia
julia> A = [1 2; 2 4]
2×2 Array{Int64,2}:
 1  2
 2  4

julia> a = Tables.matrix(Tables.table(A))
2×2 Array{Int64,2}:
 1  2
 2  4

julia> A[1, 1] = 10_000
10000

julia> a
2×2 Array{Int64,2}:
 1  2
 2  4
```

Is there a reason for wanting this behaviour?
