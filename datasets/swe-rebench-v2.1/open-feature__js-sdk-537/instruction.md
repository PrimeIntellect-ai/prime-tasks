[FEATURE] warn an implementer if they are using a client-side hook in the server-side SDK, or vice versa
### Requirements

As suggested by @beeme1mr [here](https://github.com/open-feature/js-sdk/pull/534#pullrequestreview-1566071076), it would be really good if we could give a clear warning to an OF integrater who is accidently trying to use the server SDK in a browser context, or add a server-side provider to a client-side SDK, etc etc.

### Additional contract requirements

- A provider may declare an optional `runsOn` property whose value is either `'server'` or `'client'`. When `runsOn` is omitted, the provider remains usable regardless of the SDK's runtime category.
- `OpenFeature.setProvider(provider)` must reject a provider whose `runsOn` is defined and does not match the SDK's own runtime category: the client SDK runs on `'client'` and the server SDK runs on `'server'`. The rejection is a thrown `GeneralError` (exported from `@openfeature/shared` and from the client and server SDK entry points) whose message is exactly `Provider '<name>' is intended for use on the <paradigm>.`, where `<name>` is the provider's `metadata.name` and `<paradigm>` is the provider's declared `runsOn`.
- A provider whose defined `runsOn` matches the SDK's runtime category is accepted and registered as the active provider.
