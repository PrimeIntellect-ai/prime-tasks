Bug: Closed LineStrings with repeated endpoints evaluate as non-simple
The new `IsSimpleOp` implementation has a bug which causes closed LineStrings with repeated endpoints to evaluate as non-simple.

E.g. this closed LineString:
```
LINESTRING (2 33, 1 34, 3 31, 2 33, 2 33)
```
is reported as non-simple.

Originally reported as [Shapely-1343](https://github.com/shapely/shapely/issues/1343).

### Additional contract requirements

- The `isSimple` operation must also return `true` for open LineStrings with repeated consecutive coordinates at the start, at the end, or at both ends, including a LineString whose coordinates are all identical.
