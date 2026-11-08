allow binds to merge along the `defaults->kind->node` route
right now the binds are defined on either of topology levels
It makes sense to merge them, so that the common binds might be defined on the defaults/kind level, and node specific binds will be added on the node level

### Additional contract requirements

- The merged bind list is returned by the existing public method `Topology.GetNodeBinds(name string) []string`; it combines the node-level binds with the kind-level and defaults-level binds.
