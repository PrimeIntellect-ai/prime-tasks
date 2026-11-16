Cartesian isapprox should do vector comparison instead of elementwise comparison
`isapprox(::Cartesian, ::Cartesian)` currently fails for points with `lon ≈ ±90°` (e.g. [Memphis, Tennessee](https://maps.app.goo.gl/zwZz7Tz5KLL4zzaE9)).

```julia
julia> r = convert(Cartesian, LatLon(0,0)).x
6.378137e6 m

julia> convert(Cartesian, LatLon(0, 90)) ≈ Cartesian{WGS84Latest}(0u"m", r, 0u"m")
false
```

The problem is that `isapprox(::Cartesian, ::Cartesian)` currently compares every entry one by one for approximate equality.

https://github.com/JuliaEarth/CoordRefSystems.jl/blob/14940f9ab20cf320729af1668a3629778d1b5be5/src/crs/basic.jl#L61-L65

Instead, it should do a vector comparison, `[HIDDEN]`, analogous to [how `Base` does it](https://github.com/JuliaLang/julia/blob/6737a1de25a835870641d8d1f3c507ee60e24cc0/stdlib/LinearAlgebra/src/generic.jl#L1811-L1823).
