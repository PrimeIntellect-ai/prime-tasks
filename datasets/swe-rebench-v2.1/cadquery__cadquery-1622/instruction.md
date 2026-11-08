Face support in free function sweep
Currently only edges/wires are supported.

### Additional contract requirements

- `sweep(s, path, cap=False)` in `cadquery.occ_impl.shapes` accepts as `s` a single edge or wire, a sequence of edges or wires, a `Face`, or a sequence of `Face` objects. For face inputs, the swept result preserves holes. `cap=True` creates a solid for edge/wire inputs and has no effect for face inputs. A path that cannot be converted to a single wire raises a `ValueError`.
