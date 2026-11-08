hessian doesn't work as expected
```julia
julia> using Symbolics

julia> @variables p[1:9]
1-element Vector{Symbolics.Arr{Num, 1}}:
 p[1:9]

julia> vp = collect(p)
9-element Vector{Num}:
 p[1]
 p[2]
 p[3]
 p[4]
 p[5]
 p[6]
 p[7]
 p[8]
 p[9]

julia> f = - 1.5log(5 + p[3]) - 1.5log(7 + p[1]) - 1.5log(8 - p[2]) - 1.5log(9 - p[4]) + 0.08p[4]*p[9]
-1.5log(5 + p[3]) - 1.5log(7 + p[1]) - 1.5log(8 - p[2]) - 1.5log(9 - p[4]) + 0.08p[4]*p[9]

julia> Symbolics.hessian(f, p)
9×9 Matrix{Num}:
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0

julia> Symbolics.hessian(f, vp)
9×9 Matrix{Num}:
 -(-1.5 / ((7 + p[1])^2))                     0                         0                     0  0  0  0  0     0
                        0  1.5 / ((8 - p[2])^2)                         0                     0  0  0  0  0     0
                        0                     0  -(-1.5 / ((5 + p[3])^2))                     0  0  0  0  0     0
                        0                     0                         0  1.5 / ((9 - p[4])^2)  0  0  0  0  0.08
                        0                     0                         0                     0  0  0  0  0     0
                        0                     0                         0                     0  0  0  0  0     0
                        0                     0                         0                     0  0  0  0  0     0
                        0                     0                         0                     0  0  0  0  0     0
                        0                     0                         0                  0.08  0  0  0  0     0
```
