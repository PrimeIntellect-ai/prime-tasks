make dap2 and dap4 datasets consistent in the way they reference dimensions for BaseType
In pydap, the dimensions of the container-like object like Grids, Groups, Dataset, etc are defined as follows:

```python
pyds['Group'].dimensions
>>> {'dim1': size, 'dim2': size, ..., }
```
Where `dim1`, `dim2`, ... are not fully qualifying names because they refer to local dimensions defined within the scope of the Group.

## BaseType behavior
In the BaseType pydap object, dimensions have a different syntax, because they can reference dimensions outside of the local Group. As a result, in dap4:

### DAP4
Pydap follows the syntax of the DMR, which defines the dimensions of an atomic type, as `dims`. And so:

```python
pyds['Array'].dims
>>> ['fqn_dim1', 'fqn_dim2', ...]
```
where `'fqn_dim1'` refers to the fully qualifying name of the dimension.

### DAP2
```python
pyds['Array'].dimensions
>>> ['dim1', 'dim2', ...]
```

## Proposed Solution
To be consistent with all protocols, the DAP2 should follow the behavior of DAP4. This is, `dims` and `dimensions` have different syntax and therefore the BaseType dimension names should be defined as `dims`.

### Additional contract requirements

- DAP4 DMR output for a `BaseType` must emit dimension references from its
  `dims` values, retaining fully qualified dimension names.
- The DAP2 DDS response must serialize a `BaseType`'s dimensions from its `dims`
  names, one `[name = size]` clause per dimension, in order. For example a
  `BaseType` named `var` with `dims=('y', 'x')` and shape `(2, 3)` is serialized
  as `Int32 var[y = 2][x = 3];`.
- The DAP2 DDS parser must store the parsed dimension names on the resulting
  `BaseType`'s `dims` attribute (e.g. parsing `Int32 c[c = 10];` yields a
  variable whose `dims` contains `'c'`).
