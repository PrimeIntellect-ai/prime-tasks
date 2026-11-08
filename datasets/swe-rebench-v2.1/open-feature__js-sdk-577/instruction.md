[FEATURE] Add support for a blocking setProvider
### Requirements

https://openfeature.dev/specification/sections/flag-evaluation#requirement-118

### Additional contract requirements

- Add a public method `setProviderAndWait` to the OpenFeature API with two overloads:
  - `setProviderAndWait(provider: Provider): Promise<void>` sets the default provider.
  - `setProviderAndWait(clientName: string, provider: Provider): Promise<void>` binds the provider to the named client.
- The returned promise resolves once the provider's asynchronous `initialize` method completes successfully and the provider's status becomes `READY`.
- A provider passed to either overload may already be in the `READY` state; in that case the promise still resolves.
- If `initialize` throws or rejects, the returned promise rejects with the initialization error, after emitting `ProviderEvents.Error`.
