Generate default operationId if none provided in spec
Is it possible to create a default `operationId` using a combination of the Verb & Path if the `operationId` is not provided in the spec? More often than not the author of the original spec will use exactly that semantic to generate the `operationId `name. Rather than error out [HIDDEN] just generate a default name?

The scenario I am faced is that a lot of the legacy specs, in my organization, in heavy use were authored without the need for `operationId` (since the codegen for most of the code only generated types). If this could be supported, that would be great IMO.

### Additional contract requirements

When a spec supplies an `operationId`, keep using that identifier rather than substituting the verb-and-path fallback.
