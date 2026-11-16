Add support for NURBS (`RationalBSplineManifold`)
Like this:
```julia
struct RationalBSplineManifold{Dim,Deg,T,S<:Tuple,Dim₊₁} <: AbstractRationalBSplineManifold{Dim,Deg}
    bsplinespaces::S
    controlpoints::Array{T,Dim₊₁}
    weights::Array{T,Dim}
end

struct CustomRationalBSplineManifold{Dim,Deg,C,S<:Tuple} <: AbstractRationalBSplineManifold{Dim,Deg}
    bsplinespaces::S
    controlpoints::Array{C,Dim}
    weights::Array{T,Dim}
end
```

### Additional contract requirements

- `RationalBSplineManifold` is a public type in the `BasicBSpline` module (exported), holding the B-spline spaces, the control points, and the weights.
- Add a public constructor `RationalBSplineManifold(a, w, Ps)`, where `a` is the array of control points, `w` is the array of weights with the same size as `a`, and `Ps` is a tuple of B-spline spaces with `dim.(Ps) == size(a)`. It returns a `RationalBSplineManifold`.
- A rational manifold of dimension 1, 2, or 3 is callable: `M(t1)`, `M(t1, t2)`, and `M(t1, t2, t3)` return the point on the manifold at the given parameters. A 1-dimensional call with a parameter outside `domain(bsplinespaces(M)[1])` throws a `DomainError`.
- Support `refinement(M)` and `refinement(M, k₊=k₊)` for rational manifolds of dimensions 1, 2, and 3. The manifold returned by the `k₊` call must evaluate approximately equal to `M` at in-domain parameters.
- Support `refinement(M, Ps′)` for rational manifolds of dimensions 1, 2, and 3, where `Ps′` is a tuple of target B-spline spaces that contain the original spaces. The returned manifold must evaluate approximately equal to `M` at in-domain parameters.
