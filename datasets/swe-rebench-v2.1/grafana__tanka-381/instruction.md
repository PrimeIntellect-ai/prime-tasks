Helmraiser creates naming conflicts.
I am playing with helmraiser with the [flux chart](https://github.com/fluxcd/flux/blob/master/chart/flux/templates/rbac-role.yaml#L2) which creates a `role` named `flux` in each namespace I ask it to run flux against. When I run `tk eval` I see that there is only a single object named `flux_role` in the evaluated json.

This is because resources get added to the json with only `$NAME_$KIND` as the key. [Code here](https://github.com/grafana/tanka/blob/6d99591bf404393da3e0904cc8e04e7fda42a354/pkg/helmraiser/helm.go#L99).

This leads to a few competing concerns:

- The keys need to be unique so as to not cause conflicts / overwriting keys.
- The keys need to be usable and consistent to make later jsonnet overrides easier.

Possible solutions:

1. Always name things `$NAME_$KIND_$NAMESPACE`.
    - fully explicit
    - we might not know the namespace until later (although I think we should set the namespace in the helm command. separate issue).
    - still a pain to access by a dynamic json key.
2. Keep naming as is **unless** the namespace differs from the spec namespace, then append it.
    - will usually act as it does now.
    - usually easier to consume / override.
3. Somehow make things a map by namespace, either at the top level, or inside child levels
    - still kinda hard to pull things out with jsonnet by dynamic namespace.

In any case, I'd vote that an error would be preferable to silently overwriting objects.

### Additional contract requirements

- When rendered resources would have the same map key, rendering must return an error rather than silently discard either resource.
- Resource keys must be predictable and usable for later Jsonnet overrides.
- A caller may supply the `nameFormat` option to Helm rendering. Its value is a Go `text/template` used to determine each resource's output key and may reference fields such as `.kind` and `.metadata.name`. If the format is empty, the default name format is used.
- When a name format is supplied, each resource's output key must be determined by that format, so consumers can use the resulting keys to address the corresponding resources.
