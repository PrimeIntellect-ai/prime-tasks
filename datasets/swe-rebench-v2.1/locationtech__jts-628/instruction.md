ClassCastException when reversing MultiLineString with only a single LineString
On version 1.17.1.

Since #513 was merged, a MultiLineString cannot be reversed if it only contains a single LineString.

The following is a minimal example:

```
GeometryFactory f = new GeometryFactory();

Coordinate[] coordinates = new Coordinate[2];
coordinates[0] = new Coordinate(1,1);
coordinates[1] = new Coordinate(2,2);

LineString[] lineStrings = new LineString[1];
lineStrings[0] = f.createLineString(coordinates);

MultiLineString multiLineString = f.createMultiLineString(lineStrings);
multiLineString.reverse();
```

This results in the following ClassCastException:

> java.lang.ClassCastException: class org.locationtech.jts.geom.LineString cannot be cast to class org.locationtech.jts.geom.GeometryCollection
