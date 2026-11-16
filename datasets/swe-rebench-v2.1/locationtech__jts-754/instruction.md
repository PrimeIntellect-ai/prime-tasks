IsSimpleOp does not support FindAllLocations for Polygon, MultiPoint and GeometryCollection
The following unit tests fail:
```java
  public void testPolygonAll() {
    checkIsSimpleAll("POLYGON ((0 0, 7 0, 6 -1, 6 -0.1, 6 0.1, 3 5.9, 3 6.1, 3.1 6, 2.9 6, 0 0))",
      BoundaryNodeRule.MOD2_BOUNDARY_RULE,
      "MULTIPOINT((6 0), (3 6))");
  }

  public void testMultiPointAll() {
    checkIsSimpleAll("MULTIPOINT((1 1), (1 2), (1 2), (1 3), (1 4), (1 4), (1 5), (1 5))",
      BoundaryNodeRule.MOD2_BOUNDARY_RULE,
      "MULTIPOINT((1 2), (1 4), (1 5))");
  }
  public void testGeometryCollectionAll() {
    checkIsSimpleAll("GEOMETRYCOLLECTION(MULTILINESTRING ((10 20, 90 20), (10 30, 90 30), (50 40, 50 10)), " +
      "MULTIPOINT((1 1), (1 2), (1 2), (1 3), (1 4), (1 4), (1 5), (1 5)))",
      BoundaryNodeRule.MOD2_BOUNDARY_RULE,
      "MULTIPOINT((50 20), (50 30), (1 2), (1 4), (1 5))");
  }
```
