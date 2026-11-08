OverlayNG area check heuristic causing issues when snapping noder is used
After upgrading JTS from 1.18.2 to 1.19.0 ran into a number of tests that use difference operation failing with `TopologyException: Result area inconsistent with overlay operation`.

[HIDDEN]
In our case we are performing a difference operation on two almost-exactly-the-same geometries and expect an empty result.

Note: we are using snapping noder like in [OverlayNGSnappingFunctions code](https://github.com/locationtech/jts/blob/master/modules/app/src/main/java/org/locationtech/jtstest/function/OverlayNGSnappingFunctions.java).

### Test case 1
This case fails with `TopologyException`:
```
@Test
void test2() throws ParseException {
    Geometry g1 = new WKTReader().read("MULTIPOLYGON (((0.37676311 2.57570853, 7.28652472 0.00028375, 7.60034931 0.81686059, 0.50229292 3.4551325, 0.37676311 2.57570853)))");
    Geometry g2 = new WKTReader().read("MULTIPOLYGON (((0.50229292 3.4551325, 7.60034931 0.81686059, 7.28652472 0.00028375, 0.37676311 2.57570853, 0.50229292 3.4551325)))");

    // Note: in our code we have an utility function that wraps this logic
    Geometry overlayResult = OverlayNG.overlay(
            g1,
            g2,
            OverlayNG.DIFFERENCE,
            g1.getPrecisionModel(),
            new ValidatingNoder(new SnappingNoder(1e-4))
    );

    assertTrue(overlayResult.isEmpty());
}
```
[HIDDEN]

### Test case 2
This case passes with the same data:
```
@Test       // Passes
void test() throws ParseException {
    Geometry p1 = new WKTReader().read("MULTIPOLYGON (((0.37676311 2.57570853, 7.28652472 0.00028375, 7.60034931 0.81686059, 0.50229292 3.4551325, 0.37676311 2.57570853)))");
    Geometry p2 = new WKTReader().read("MULTIPOLYGON (((0.50229292 3.4551325, 7.60034931 0.81686059, 7.28652472 0.00028375, 0.37676311 2.57570853, 0.50229292 3.4551325)))");

    Geometry result = p1.difference(p2);

    assertEquals(result.getArea(), 0);
}
```
[HIDDEN]

### Question
To me this feels like a bug in the heuristic check, but maybe our utility function for the difference operation is implemented in a suboptimal way?

If it's indeed a bug, and the fix is relatively simple (for someone who does not know JTS internals well), we'd be happy to contribute a PR with the fix.
