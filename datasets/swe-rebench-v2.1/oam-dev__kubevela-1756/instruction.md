we should add some `keyword` such as `//+ignore` to let the user can't see the parameter and only be used by system.
we should add some `keyword` such as `//+ignore` to let the user can't see the parameter and only be used by system.

_Originally posted by @wonderflow in https://github.com/oam-dev/kubevela/pull/1748#r644563466_

### Additional contract requirements

- A CUE parameter annotated with `//+ignore` is system-only: it must be omitted from the user-facing parameter reference produced for a capability, while parameters without the annotation are still listed.
- The `Parameter` type in `apis/types` carries an `Ignore` boolean that is `true` exactly for parameters annotated with `//+ignore`, and this flag is exposed in the parameter's JSON form under the key `ignore`.
