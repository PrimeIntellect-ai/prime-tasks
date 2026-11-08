`ProjectTo` is not defined for `NamedDimsArray`
```julia
julia> nda = NamedDimsArray{(:a, :b)}(rand(3, 3))
3×3 NamedDimsArray(::Matrix{Float64}, (:a, :b)):
     → b
↓ a  0.670477  0.9866    0.292266
     0.317949  0.926949  0.76807
     0.99007   0.473338  0.560692

julia> project = ProjectTo(nda)
ProjectTo{AbstractArray}(element = ProjectTo{Float64}(), axes = (Base.OneTo(3), Base.OneTo(3)))

julia> project(rand(3, 3))
3×3 Matrix{Float64}:
 0.0611735  0.684982  0.6573
 0.601941   0.336996  0.782579
 0.477275   0.499212  0.697885
```

whereas it should return a NamedDimsArray.
