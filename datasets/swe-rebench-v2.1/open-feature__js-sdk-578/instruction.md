Add utility function to clear providers for testing purposes
### Requirements

When writing tests we can observe some weird behavior because there is no way to unlink providers from the `Openfeature` singleton.

It could be great to have a way to clear the providers from the singleton to be able to create new tests that are not dependent on the previous situation of the singleton.
I am thinking of something similar to [`clearHooks`](https://github.com/open-feature/js-sdk/blob/95332ab5b2cc523b0ec7104d7e72c8a693887209/packages/shared/src/open-feature.ts#L45).

### Additional contract requirements

- Add a public method `clearProviders(): Promise<void>` on the `OpenFeature` singleton, available in both the client and server packages. Calling it removes all registered providers and resets the default provider to the no-op implementation.


- - The no-op provider's metadata name must be exactly `No-op Provider`.
