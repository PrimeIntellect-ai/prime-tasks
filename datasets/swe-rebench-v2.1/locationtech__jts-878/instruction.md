Buffer of closed LineString has "inverted hole" artifact
Buffering this closed line with distance = 70 produces a polygon with an incorrect hole artifact.  If an endpoint is moved slightly to make the line non-closed, the buffer is computed correctly.
```
LINESTRING (-20 0, 0 20, 20 0, 0 -20, -20 0)
```

![image](https://user-images.githubusercontent.com/3529053/171037783-be9acfc2-cd2a-49ad-bc5e-dcd5c7861797.png)

Original report: https://github.com/shapely/shapely/discussions/1405

This is due to the [optimization](https://github.com/libgeos/geos/commit/733bddf9483ad562c86882361d67b2c662af304f#diff-27855ad956223b890a18502e0f8e51503d7dcf2ff5a4527fbdfdc53c45d16c94R373) in the heuristic to detect "inverted rings" [HIDDEN]

### Additional contract requirements

- Buffering the supplied closed LineString by distance 70 must produce a polygon without the incorrect hole artifact.
