Invalid LinearRing is reported as valid
Certain kinds of LinearRings with self-intersections are reported as valid by `Geometry.isValid()`. For example:
```
LINEARRING (40 90, 90 90, 10 10, 90 10, 40 90)
```
![image](https://user-images.githubusercontent.com/3529053/120845206-56767e00-c525-11eb-8c02-92cafdcb0f40.png)

This is caused by a bug in the way `IsValidOp` analyzes the self-intersections.  Roughly, if the self-intersection is to the left of the ring endpoint, it is not detected as being invalid.

Originally reported as [Shapely-1133](https://github.com/Toblerity/Shapely/issues/1133)
