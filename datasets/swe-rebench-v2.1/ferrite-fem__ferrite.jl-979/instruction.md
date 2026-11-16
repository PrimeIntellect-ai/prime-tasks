`FacetValue` does not seem to be type stable
```
using Test

qr      = QuadratureRule{RefQuadrilateral}(2)
facet_qr = FacetQuadratureRule{RefQuadrilateral}(2)
ip = Lagrange{RefQuadrilateral,1}()^2
@inferred FacetValues(facet_qr, ip)

ERROR: return type FacetValues{Ferrite.FunctionValues{1, VectorizedInterpolation{2, RefQuadrilateral, 1, Lagrange{RefQuadrilateral, 1, Nothing}}, Matrix{Vec{2, Float64}}, Matrix{Tensor{2, 2, Float64, 4}}, Matrix{Tensor{2, 2, Float64, 4}}, Nothing, Nothing}, Ferrite.GeometryMapping{1, Lagrange{RefQuadrilateral, 1, Nothing}, Matrix{Float64}, Matrix{Vec{2, Float64}}, Nothing}, FacetQuadratureRule{RefQuadrilateral, Float64, 2}, Vector{Float64}, Vector{Vec{2, Float64}}, Vector{Ferrite.FunctionValues{1, VectorizedInterpolation{2, RefQuadrilateral, 1, Lagrange{RefQuadrilateral, 1, Nothing}}, Matrix{Vec{2, Float64}}, Matrix{Tensor{2, 2, Float64, 4}}, Matrix{Tensor{2, 2, Float64, 4}}, Nothing, Nothing}}, Vector{Ferrite.GeometryMapping{1, Lagrange{RefQuadrilateral, 1, Nothing}, Matrix{Float64}, Matrix{Vec{2, Float64}}, Nothing}}} does not match inferred return type FacetValues{var"#s127", var"#s1271", FacetQuadratureRule{RefQuadrilateral, Float64, 2}, Vector{Float64}, Vector{Vec{2, Float64}}, V_FV, V_GM} where {var"#s127"<:(Ferrite.FunctionValues{DiffOrder, VectorizedInterpolation{2, RefQuadrilateral, 1, Lagrange{RefQuadrilateral, 1, Nothing}}, Matrix{Vec{2, Float64}}} where DiffOrder), var"#s1271"<:(Ferrite.GeometryMapping{DiffOrder, Lagrange{RefQuadrilateral, 1, Nothing}, Matrix{Float64}} where DiffOrder), V_FV<:AbstractVector{var"#s127"}, V_GM<:AbstractVector{var"#s1271"}}
```

The following diff seems to solve it which is kind of stupid

```diff
diff --git a/src/FEValues/FacetValues.jl b/src/FEValues/FacetValues.jl
index e4268c1ed..ebc96535f 100644
--- a/src/FEValues/FacetValues.jl
+++ b/src/FEValues/FacetValues.jl
@@ -56,15 +56,18 @@ function FacetValues(::Type{T}, fqr::FacetQuadratureRule, ip_fun::Interpolation,
     FunDiffOrder = _update_hessians ? 2 : (_update_gradients ? 1 : 0)
     GeoDiffOrder = max(required_geo_diff_order(mapping_type(ip_fun), FunDiffOrder), 1)

-    geo_mapping = [GeometryMapping{GeoDiffOrder}(T, ip_geo.ip, qr) for qr in fqr.face_rules]::Vector{<:GeometryMapping{GeoDiffOrder}}
-    fun_values = [FunctionValues{FunDiffOrder}(T, ip_fun, qr, ip_geo) for qr in fqr.face_rules]::Vector{<:FunctionValues{FunDiffOrder}}
[HIDDEN]
     max_nquadpoints = maximum(qr->length(getweights(qr)), fqr.face_rules)
     detJdV  = fill(T(NaN), max_nquadpoints)
     normals = fill(zero(Vec{sdim, T}) * T(NaN), max_nquadpoints)
     return FacetVa
```
