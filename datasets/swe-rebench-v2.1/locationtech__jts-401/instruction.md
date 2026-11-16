LinearLocation::setToEnd - invalid segmentFraction
I would expect that segmentFraction will be set to 0.0 instead of 1.0. Because segmentIndex is already set to last coordinate.
  When I call LocationIndexedLine::project(<last_coordinate>) I get same component and segment indices but segmentFraction will be 0.0 (correct value). So I can't compare this LinearLocation with LocationIndexedLine::getEndIndex.

Current code:
```
  public void setToEnd(Geometry linear)
  {
    componentIndex = linear.getNumGeometries() - 1;
    LineString lastLine = (LineString) linear.getGeometryN(componentIndex);
    segmentIndex = lastLine.getNumPoints() - 1;
    segmentFraction = 1.0;
  }

```

Correct code:
```
  public void setToEnd(Geometry linear)
  {
    componentIndex = linear.getNumGeometries() - 1;
    LineString lastLine = (LineString) linear.getGeometryN(componentIndex);
    segmentIndex = lastLine.getNumPoints() - 1;
    [HIDDEN]
  }

```

PS I suggest to extend LinearLocation with equals + hashCode.

### Additional contract requirements

- After `LinearLocation.setToEnd(geometry)` is called, the resulting location refers to the last vertex of the last component. Its segment fraction must be `0.0`, not `1.0`, so that it matches the location produced when projecting the last coordinate of the geometry.
