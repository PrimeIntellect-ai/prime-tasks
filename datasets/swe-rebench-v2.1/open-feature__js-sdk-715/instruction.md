[FEATURE] Named provider metadata accessor
### Requirements

Add support for accessing provider metadata for named providers. If a name is invalid, the default provider metadata should be returned.

### Additional contract requirements

Add a public method `OpenFeature.getProviderMetadata(clientName?: string)` on the shared `OpenFeature` API singleton that returns the `ProviderMetadata` of the provider registered for the given client name. When the client name is omitted, empty, or not registered, the default provider's metadata is returned.
