Line Segment GetHashCode is prone to hash collision
I have been using the NTS version of this library and found that the [LineSegment.hashCode()](
https://github.com/locationtech/jts/blob/29cce2c8442eda9d58e907377db1c3ab6edce9ea/modules/core/src/main/java/org/locationtech/jts/geom/LineSegment.java#L643) implementation yields collisions far too often.

I made a simple test which fails.
```java
public void testHashCode() {
	  LineSegment seg = new LineSegment(0, 0, 10, 0);
	  LineSegment seg2 = new LineSegment(0, 10, 10, 10);
	  assertNotEquals(seg.hashCode(), seg2.hashCode());
  }
```

I would expect that parallel LineSegements would not have the same hashcode.

>... This is also important because other libraries expect that `hashCode()` and `equals()` are implemented correctly. If two objects are equal and they have the same hash code, they should be interchangeable, but they aren't. ...
>
>_Originally posted by @janruo in https://github.com/locationtech/jts/issues/366#issuecomment-573723473_


I made a request against NTS, but they would prefer to maintain parity with JTS, so I am submitting the issue here as well.
My Java isn't as strong as my C#, so I wouldn't be 100% sure how to submit a similar implementation as I have for C#


NTS Upstream links:
https://github.com/NetTopologySuite/NetTopologySuite/issues/607
https://github.com/NetTopologySuite/NetTopologySuite/pull/608

### Additional contract requirements

- `LineSegment.hashCode()` must return an `int` derived from all four endpoint coordinates, with improved distribution to reduce frequent collisions.
- Distinct segments should rarely share a hash code: for a 20 x 20 grid of distinct unit-spaced horizontal and vertical segments (800 segments in total), at least 90% of the segments must have distinct hash codes.
- In particular, `new LineSegment(0, 0, 10, 0)` and `new LineSegment(0, 10, 10, 10)` must have different hash codes. Collisions between distinct segments may still occur.
