grid.interp_like()
I propose a small addition to xgcm Axis/Grid.

`grid.interp_like(da, da_target)` (adopting naming from xarray) would determine which axes are found in both `da` and `da_target` and if da is not on the same axis position as `da_target` use interpolation along the axis to 'move' `da` to the adjacent coordinate.

I found this would be very helpful in many contexts that I have encountered in the past.

Happy to put in a PR soon, but wanted to discuss  first.
