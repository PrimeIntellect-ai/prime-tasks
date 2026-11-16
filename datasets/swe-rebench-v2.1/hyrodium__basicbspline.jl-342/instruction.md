`changebasis_I` sometimes returns a matrix with `NaN`
```julia
julia> using BasicBSpline

julia> Pd1 = BSplineSpace{3}(knotvector"44 3  2 121 ")
BSplineSpace{3, Int64, KnotVector{Int64}}(KnotVector([1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 7, 7, 9, 10, 10, 11]))

julia> Pd2 = BSplineSpace{4}(knotvector"55 62 3 2121")
BSplineSpace{4, Int64, KnotVector{Int64}}(KnotVector([1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 5, 5, 7, 7, 7, 9, 9, 10, 11, 11, 12]))

julia> changebasis_I(Pd1, Pd2)
13×22 SparseArrays.SparseMatrixCSC{Float64, Int32} with 44 stored entries:
⎡⠙⢦⡀⠀⠀⠀⠀⠀⠀⠀⠀⎤
⎢⠀⠀⠈⠳⣄⢀⣀⡀⠀⠀⠀⎥
⎢⠀⠀⠀⠀⠀⠀⠙⠿⠶⣤⣤⎥
⎣⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⎦
```
