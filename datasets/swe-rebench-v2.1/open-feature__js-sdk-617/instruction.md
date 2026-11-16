[FEATURE] In-memory provider for js (node) and web SDKs
### Requirements

As outlined [in the specification](https://openfeature.dev/specification/appendix-a#in-memory-provider), the js-sdk should include an in-memory provider implementation. This implementation should take a simple object that defines flags as well as simple rules in the form of lambdas (see equivalent [Java implementation](https://github.com/open-feature/java-sdk/blob/main/src/main/java/dev/openfeature/sdk/providers/memory/InMemoryProvider.java), and existing [JS implementation](https://github.com/open-feature/js-sdk-contrib/tree/main/libs/providers/in-memory) in contrib) and use those to evaluate flags. This is very useful to conusmers of the SDK for testing purposes. Please carefully implement all the behaviors defined in the spec for the in-memory provider.

This is a great issue to take on if you're looking to get started in OpenFeature!

@moredip This would be pretty similar to what you implemented in the JS contrib. I think the main thing missing would be rules-based evaluation (some flag "values" would instead define lambdas to run which are passed the context). If you'd like to work on this issue, just assign it to yourself. Otherwise, I will add the `good first issue`, etc tags to it which I suspect will result in it quickly being picked up.
```[tasklist]
### Tasks
- [ ] web-sdk implementation (`packages/client`)
- [x] js-sdk (node) implementation (`packages/server`)
- [ ] remove existing partial implementation from js-sdk-contrib
```

### Additional contract requirements

- The optional evaluation context supplied to each resolution method is forwarded to a flag's `contextEvaluator` as its argument during resolution.
- When a `Logger` is supplied to a resolution method, the provider reports resolution errors to it: a missing flag is reported via `logger.debug(...)` and a missing variant via `logger.error(...)`.
- The client package entry point exposes the provider as `InMemoryProvider`.
- A provider configuration maps flag keys to flag definitions. Each definition has a `variants` map from variant names to boolean, string, number, or JSON values, a `defaultVariant` naming the variant used for static evaluation, and a `disabled` boolean. A disabled flag resolves to the caller's default value; otherwise the configured variant value is used. A definition may include a `contextEvaluator` function that receives the evaluation context during resolution and returns the variant name to use.
