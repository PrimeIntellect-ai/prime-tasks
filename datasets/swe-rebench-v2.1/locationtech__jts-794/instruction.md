RectangleIntersect on an XYZM coordinate sequence fails - Invalid ordinate index: 3
This is the root cause of https://osgeo-org.atlassian.net/browse/GEOS-10290 when GeoServer/GeoTools tries to access a XYZM shapefile we get the following exception thrown. [HIDDEN]

```
Caused by: java.lang.IllegalArgumentException: Invalid ordinate index: 3
	at org.locationtech.jts.geom.Coordinate.setM(Coordinate.java:218)
	at org.locationtech.jts.geom.impl.PackedCoordinateSequence.getCoordinate(PackedCoordinateSequence.java:116)
	at org.locationtech.jts.operation.predicate.RectangleIntersectsSegmentVisitor.checkIntersectionWithSegments(RectangleIntersects.java:327)
	at org.locationtech.jts.operation.predicate.RectangleIntersectsSegmentVisitor.checkIntersectionWithLineStrings(RectangleIntersects.java:317)
	at org.locationtech.jts.operation.predicate.RectangleIntersectsSegmentVisitor.visit(RectangleIntersects.java:310)
	at org.locationtech.jts.geom.util.ShortCircuitedGeometryVisitor.applyTo(ShortCircuitedGeometryVisitor.java:35)
	at org.locationtech.jts.operation.predicate.RectangleIntersects.intersects(RectangleIntersects.java:110)
	at org.locationtech.jts.operation.predicate.RectangleIntersects.intersects(RectangleIntersects.java:58)
	at org.locationtech.jts.geom.Geometry.intersects(Geometry.java:754)
```

### Additional contract requirements

- For geometries with XYZM coordinate sequences, `RectangleIntersects` must evaluate intersection without throwing the reported invalid-ordinate exception and return the geometrically correct boolean result.
