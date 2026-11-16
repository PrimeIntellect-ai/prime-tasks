Create a `grid.negate_depth` method to swap the sign of depth fields?
Since the sign/orientation of the depth vector is not standardised in oceanography, users may sometimes need to negate a `grid.depth` field. See e.g. https://github.com/OceanParcels/virtualship/pull/75. Especially since `grid._depth` is a private attribute, this is not trivial to users.

It might thus be useful to add a simple `grid.negate_depth()`method that simply does
```python
[HIDDEN]
```

### Additional contract requirements

- Calling `grid.negate_depth()` reverses the signs of the grid’s depth values in place; subsequent access to `grid.depth` returns the reversed values.
