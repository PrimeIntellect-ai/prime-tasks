WKT decimals precision
Hi,
there's a problem with the .wkt() function.
For example :
- I have a GeoJSON file with one point, with coordinates   x : -0.4225977, y : 46.3406448
- the GeoJSON object stores coordinates with a Double format. In debugger, values are x : -0.4225977**0000000002**, y : 46,3406448
- the string generated with wkt() contains the debugger values instead of the real ones
I think the generated string from my real data is twice the size it should be :(

### Additional contract requirements

WKT writing is available through `wkt(useFixedPrecision: Bool, roundingPrecision: Int32)`, which returns WKT and accepts a Boolean selecting fixed-precision trimming and a precision in decimal places. The selected rounding precision controls the emitted coordinate values; a precision of -1 uses the writer's default precision. When fixed-precision trimming is selected, unnecessary trailing fractional zeros are removed from emitted coordinates.
