Allow conversion `LatLon{WGS84Latest}` --> `Mercator{ITRF{2008}}`
MWE:

```julia
julia> convert(Mercator{ITRF{2008}}, LatLon{WGS84Latest}(0,0))
ERROR: MethodError: Cannot `convert` an object of type
  GeodeticLatLon{WGS84Latest, Unitful.Quantity{Float64, NoDims, Unitful.FreeUnits{(°,), NoDims, nothing}}} to an object of type
  Mercator{ITRF{2008}}
```
