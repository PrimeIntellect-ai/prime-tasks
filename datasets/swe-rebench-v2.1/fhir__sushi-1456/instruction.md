Support propagation of version, status, publisher to FSH-Only IGs
SUSHI 3.0 removed automatic propagation of version and status since the IG Publisher does this already (and in a more sophisticated manner). Authors using SUSHI in FSH-Only mode, however, don't use the IG Publisher, and therefore do not benefit from its built-in propagation of these properties.

We should consider adding back support for propagating these properties. In order to not introduce what might be deemed a breaking change, we should consider making this behavior opt-in via `sushi-config.yaml` configuration. We will need to determine the format of that config (multiple properties, single property w/ multiple values, etc) and whether it should apply only to FSH-Only IGs or to any IG that sets those config properties.

See: https://chat.fhir.org/#narrow/stream/179252-IG-creation/topic/Profiles.20Versioning/near/400510389

### Additional contract requirements

The opt-in behavior is controlled by the existing `FSHOnly` property in `sushi-config.yaml`. When `FSHOnly` is `true`, the top-level `version` and `status` properties of `sushi-config.yaml` are propagated as default metadata to every exported StructureDefinition (profiles, extensions, logical models, and resources), ValueSet, and CodeSystem:

- The exported resource's `version` is set to the `version` value from `sushi-config.yaml`.
- The exported resource's `status` is set to the `status` value from `sushi-config.yaml`.
- When `FSHOnly` is not `true`, `version` is not propagated (it is left for the IG Publisher to set), while `status` continues to be set from `sushi-config.yaml` as before.
- In FSH-Only mode, `status` is a valid configuration property and must not be reported as an unused/IG-creation-only property.

Scope: although the title also names `publisher`, the required behavior for this task is limited to propagation of `version` and `status`; propagation of `publisher` is out of scope.
