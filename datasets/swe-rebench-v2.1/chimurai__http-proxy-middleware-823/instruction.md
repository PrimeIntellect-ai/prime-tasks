Errors in prepareProxyRequest not handled for websockets
### Checks

- [X] I understand project setup issues should be asked on [StackOverflow](https://stackoverflow.com/questions/tagged/http-proxy-middleware) or in [GitHub Discussions](https://github.com/chimurai/http-proxy-middleware/discussions).
- [X] I updated to latest `http-proxy-middleware`.

### Describe the bug (be clear and concise)

The callsites of `handleUpgrade` do not handle errors thrown from `prepareProxyRequest`. For a user, this means that any error thrown in `router` or `pathRewrite` will result in an `unhandledRejection`.

[HIDDEN]

https://github.com/chimurai/http-proxy-middleware/blob/79c9885eb2b8ed1bc201182175b733b738873f5e/src/http-proxy-middleware.ts#L34

https://github.com/chimurai/http-proxy-middleware/blob/79c9885eb2b8ed1bc201182175b733b738873f5e/src/http-proxy-middleware.ts#L88

### Step-by-step reproduction instructions

Add a `router` or `pathRewrite` function that throws an error, then try to make a websocket request. Observe that the error is not handled. E.g., if you add an `onError` handler to the proxy config, it is not called, and if you `process.on('unhandledRejection', (e) => console.error(e))`, that error is logged.

### Expected behavior (be clear and concise)

`onError` should be invoked so that I can handle the error appropriately.

### How is http-proxy-middleware used in your project?

It is installed as a direct dependency.

### What http-proxy-middleware configuration are you using?

Here's a pared-down version:

```typescript
const options = {
  router: async () => {
    throw new Error('testing');
  },
  onError: (err, req, res) => {
    // Not called for websocket requests
    res.status(500).send();
  },
};
```

### What OS/version and node/version are you seeing the problem?

```shell
macOS 12.5.1; Node v16.17.0
```

### Additional contract requirements

- The error handler is configured through the `on.error` option of `createProxyMiddleware`. When preparing a WebSocket proxy request fails (for example, because the `router` or `pathRewrite` throws), that configured error handler is invoked with the error.
