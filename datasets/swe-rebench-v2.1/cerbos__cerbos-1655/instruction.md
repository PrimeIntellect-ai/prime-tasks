Allow for evaluating a scope hierarchy with absent top level scope
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Feature description

Allow for policy evaluation to be performed as long as some level of the scope hierarchy is available for a resource scope. For example, given a resource scope of `a.b.c` and resource policies existing with each of scopes ``, `a`, `a.b`, the policy evaluation of the resource should use these 3 three scopes, ignoring the fact that there is no `a.b.c` policy scope defined. The current behavior results in a `NO_MATCH` and denied response.

### What would the ideal solution look like to you?

Ideally, the default behavior would be to use whatever base hierarchy exists, skipping the higher level scopes that are not defined. An alternative to changing the default behavior (which obviously has backwards compatibility issues), is to add a request option that specifies to find the defined scope hierarchy and to ignore missing top level hierarchies.

### Anything else?

_No response_

### Additional contract requirements

- The engine configuration must expose a boolean option named `lenientScopeSearch` (config key `engine.lenientScopeSearch`). When it is enabled, policy evaluation must search up the scope hierarchy as described above. The exported field on the engine configuration struct is `LenientScopeSearch`.
- Add `ScopedResourcePolicyModuleIDs(resource, version, scope string, genTree bool) []namer.ModuleID` in package `github.com/cerbos/cerbos/internal/namer`. With `genTree` true and a non-empty `scope`, it returns the module IDs for the full scope followed by each parent scope down to the empty scope, in that order. With `genTree` false, or with an empty `scope`, it returns a single module ID for the exact scope.
- Add `ScopedPrincipalPolicyModuleIDs(principal, version, scope string, genTree bool) []namer.ModuleID` in package `github.com/cerbos/cerbos/internal/namer`, with the same behaviour for principal policies.
- Add `GetFirstMatch([]namer.ModuleID) (*policy.CompilationUnit, error)` in package `github.com/cerbos/cerbos/internal/storage/index`. It returns the compilation unit of the first candidate module ID that exists in the index, including that policy's dependencies and its scope ancestors, or `nil` when no candidate exists.
- Add `GetFirstMatch(context.Context, []namer.ModuleID) (*runtimev1.RunnablePolicySet, error)` to the `PolicyLoader` interface in package `github.com/cerbos/cerbos/internal/engine` and to the `BinaryStore` interface in package `github.com/cerbos/cerbos/internal/storage`. It returns the runnable policy set for the first candidate found, or `nil` when none exists.
- Add `GetFirstMatch(context.Context, []namer.ModuleID) (*runtimev1.RunnablePolicySet, error)` on the overlay store in package `github.com/cerbos/cerbos/internal/storage/overlay`. It returns the runnable policy set for the first candidate found.
