issue indexing dynamic table region with slice
## 1) Bug

There is currently a bug when using a `slice` to access a region of a `DynamicTableRegion`. [HIDDEN] Instead, the `slice` indexes `[0, 1, 2, ...]`.

(This was my mistake. I did something goofy and it looks like I didn't have a good understanding of slice indexing at the time. The fix is pretty straightforward.)

If you are reporting a bug please provide the following:
### Steps to Reproduce
```python
from pynwb.core import DynamicTableRegion
dtr = DynamicTableRegion('name', [0,1,1], 'desc', nwb.electrodes)
dtr[:2]
```

## Checklist

- [x] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?

### Additional contract requirements

- When a `DynamicTableRegion` is indexed with a slice, it must return the corresponding rows from its associated `DynamicTable`, preserving the selected entries’ order and repetitions.
