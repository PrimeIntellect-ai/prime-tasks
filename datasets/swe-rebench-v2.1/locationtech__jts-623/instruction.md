WKB representation of POLYGON EMPTY
When JTS makes a WKB for POLYGON EMPTY, it strangely specifies that there is 1 ring with 0 coordinates.  Esri specifies 0 rings.  Both libraries parse both forms of WKB fine.

The WKB spec for polygons, as I've parsed it (please correct me if wrong!) is:
1 byte: big/little endian
4 bytes: uint32 specifying geometry type (3 for polygon)
4 bytes: uint32 specifying how many rings
for each ring:
  4 bytes: uint 32 specifying how many points in the ring
  for each point:
    8 bytes: double specifying x-coordinate
    8 bytes: double specifying y-coordinate

OGC does not specify how to handle empty geometries (as usual).

When JTS makes a WKB for a POLYGON EMPTY, it produces the expected endian and type bytes.  It then has a 1 in the 5th byte, and a 0 in the 6th byte.  (Esri has a 0 in the 5th byte, and no 6th byte).  This is making cross-library testing slightly more challenging, and the esri version is more intuitive to me.  However, I can't say that either version is "to spec", since it's underspecified.

Thoughts?

### Additional contract requirements

- When WKBWriter writes POLYGON EMPTY in little-endian order, it must encode zero rings. The exact hexadecimal WKB must be `010300000000000000` for dimension 2, `010300008000000000` for dimension 3, and `0103000020E610000000000000` for dimension 2 with SRID inclusion enabled and geometry SRID 4326.
