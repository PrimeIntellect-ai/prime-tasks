[HIDDEN]
This will help preserve the `scale` vector in a roundtrip from components -> matrix -> components.

This should resolve the problem observed in #553

This requires a fix in pylinalg, see https://github.com/pygfx/pylinalg/issues/81

### Additional contract requirements

- When a transform's scale is set, a subsequent components → matrix → components roundtrip must preserve the set scale vector, including the sign of each axis.
- For a `WorldObject` with local scale `(1, -2, 3)` and an identity child, the child's local scale must be `[1, 1, 1]` and its world scale must be `[-1, 2, 3]`.
