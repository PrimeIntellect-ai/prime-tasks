addeq SeriesElem
```julia
Qx, x = PowerSeriesRing(GF(13), 10, "x");
a = Qx([GF(13)(1)], 1, 3, 0)
c = Qx([GF(13)(1)], 1, 7, 4)
addeq!(c, a)
```
->

ERROR: BoundsError: attempt to access 3-element Array{Nemo.gfp_elem,1} at index [5]
