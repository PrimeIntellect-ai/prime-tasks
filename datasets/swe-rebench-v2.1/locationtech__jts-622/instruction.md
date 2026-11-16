WKB POINT EMPTY does not handle 3D
The POINT EMPTY handler writes out a fixed 2 NaN values for coordinates, regardless of whether the output is of higher dimensionality.

https://github.com/locationtech/jts/blob/master/modules/core/src/main/java/org/locationtech/jts/io/WKBWriter.java#L347
