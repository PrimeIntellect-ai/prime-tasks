Make `Shape` immutable and hashable
It has never been intended that a `Shape` could be mutated.

### Additional contract requirements

- `Shape` is immutable after construction: assigning to the public `width` or `signed` attributes raises `AttributeError`, and the shape's width and signedness are unchanged.
- `Shape` instances are hashable and can be used as dictionary keys or set members. Equal shapes have equal hashes.
