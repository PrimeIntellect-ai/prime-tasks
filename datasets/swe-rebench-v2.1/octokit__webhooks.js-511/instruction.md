Deprecate `createWebhooksApi`
The `createWebhooksApi` export is there for legacy reasons. We use constructors across the other @octokit modules

https://github.com/octokit/webhooks.js/blob/1891034b602a2193a08f1ac3ad31775df65ca578/src/index.ts#L69

We should deprecate `createWebhooksApi` by exporting a function with that name that logs a deprecation message and returns a `Webhooks` instance with the same options, then remove it as v9.

I like creating a dedicated `deprecations-test.ts` file where we test that the deprecation message is logged and that the API still works. If we stay consistent with that flow, removing deprecated APIs as part of a breaking release becomes trivial

### Additional contract requirements

- `createWebhooksApi` is exported from `src/index.ts` and accepts an options object (for example `{ secret: "foo" }`), returning a `Webhooks` instance initialized with those options.
- The deprecation message written to `console.error` is exactly: `[@octokit/webhooks] \`createWebhooksApi()\` is deprecated and will be removed in a future release of \`@octokit/webhooks\`, please use the \`Webhooks\` class instead`
