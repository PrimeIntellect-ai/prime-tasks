[BUG] `CSWAP` and `CRot` are missing its `control_wires` attribute
`qml.CSWAP` and `qml.CRot`  are both controlled operations, but neither define their `control_wires` attribute.

### Additional contract requirements

- `control_wires` is exposed as a property (attribute) on each operation, not as a
  callable method. Accessing `op.control_wires` directly returns a `Wires` instance.
- `qml.SWAP.control_wires` returns an empty `Wires()` instance.
- `qml.CSWAP.control_wires` returns a `Wires` containing the operation's first wire.
- `qml.CRot.control_wires` returns a `Wires` containing the operation's first wire.
