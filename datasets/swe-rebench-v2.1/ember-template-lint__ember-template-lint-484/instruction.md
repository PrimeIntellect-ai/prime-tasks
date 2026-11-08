no-implicit-this and hasBlock
The `no-implicit-this` rule complains about `hasBlock` but `hasBlock` should not be used with either `this`, nor with `@` (as it returns `undefined`). Perhaps this rule can implicitly ignore `hasBlock`.
