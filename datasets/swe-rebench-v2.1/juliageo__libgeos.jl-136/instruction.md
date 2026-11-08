create multi geometries from vector of single geometries
```julia
using LibGEOS, GeoInterface

# 3 overlapping circles in a triangle
circles = [
    buffer(Point(0.0, 0.0), 1.0),
    buffer(Point(1.0, 0.0), 1.0),
    buffer(Point(0.5, 1.0), 1.0),
]

# now if from these 3 polygons we want to create a single MultiPolygon
# you might expect this to work:
MultiPolygon(circles)
# but you get -> ERROR: LoadError: MethodError: no method matching MultiPolygon(::Vector{Polygon})
# going through the GeoInterface constructor works, but will be less efficient
MultiPolygon(GeoInterface.coordinates(circles))
```
https://github.com/JuliaGeo/LibGEOS.jl/blob/e1f2b25d2002ed5b8f0b8d249ecf3f26db575a40/src/geos_types.jl#L81-L95

This probably goes for all multi geometries, not just multipolygon.

### Additional contract requirements

`MultiPoint` must also accept a vector of `Point` objects and produce a multipoint containing each supplied point. `MultiPolygon` must accept a vector of `Polygon` objects and produce a multipolygon containing each supplied polygon.
