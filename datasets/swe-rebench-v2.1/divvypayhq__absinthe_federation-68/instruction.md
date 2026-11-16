Entity resolver doesn't resolve the correct type for typenames with multiple words
The [entity type resolver](https://github.com/DivvyPayHQ/absinthe_federation/blob/v0.3.1/lib/absinthe/federation/schema/entity_union.ex#L69) uses `String.downcase/2` and fails if the `typename` is something like UserSettings. [HIDDEN]

### Additional contract requirements

When determining an entity type from a typename, the resolver must honor the adapter supplied for the GraphQL operation when translating that name.
