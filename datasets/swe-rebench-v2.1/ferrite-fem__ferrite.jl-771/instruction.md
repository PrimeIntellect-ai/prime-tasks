Showing FaceValues in the REPL is broken
```julia-repl
    ip = Lagrange{RefQuadrilateral, 1}()^2
    qr_face = FaceQuadratureRule{RefQuadrilateral}(2)
    fv_ele = FaceValues(qr_face, ip)
```

Gives

```
Error showing value of type FaceValues{VectorizedInterpolation{2, RefQuadrilateral, 1, Lagrange{RefQuadrilateral, 1, Nothing}}, Vec{2, Float64}, Tensor{2, 2, Float64, 4}, Tensor{2, 2, Float64, 4}, Float64, Vec{2, Float64}, FaceQuadratureRule{RefQuadrilateral, Float64, 2}, Vec{2, Float64}, Lagrange{RefQuadrilateral, 1, Nothing}}:
ERROR: BoundsError: attempt to access 4-element Vector{QuadratureRule{RefQuadrilateral, Float64, 2}} at index [0]
```
