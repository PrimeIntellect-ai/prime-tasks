ConcaveHullOfPolygons does not handle shells nested inside holes
The `ConcaveHullOfPolygons` class does not handle MultiPolygons with shells nested inside holes.  It produces an error in this situation: `Unable to find shell join index with interior join line`.

### Example
```
MULTIPOLYGON (((1 9, 9 9, 9 1, 1 1, 1 9), (2 8, 8 8, 8 2, 2 2, 2 8)), ((3 3, 4 7, 7 4, 3 3)))
```
<img width="201" alt="image" src="https://github.com/user-attachments/assets/b2284e0c-a8aa-4ac4-b111-7b9d6ac746d6">

### Analysis
This is because [HIDDEN] does not check for shells inside holes, and thus does not remove them.

[HIDDEN]

Originally reported as https://trac.osgeo.org/postgis/ticket/5665.

### Additional contract requirements

- For a MultiPolygon containing a polygon shell nested inside another polygon’s hole, the concave-hull operation must complete without the reported shell-join error.
