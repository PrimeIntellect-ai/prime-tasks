Graphql URI
Hey, everyone
Could I somehow provide graphql URI?

For example, I need to set up service on `/` endpoint instead of `/graphql`.

I had next code for `apollo-server-hapi` library
```js
await graphqlServer.applyMiddleware({ app: server, path: '/' });
```

I guess it can be a little bit simpler (for example, parameter `path` in the constructor).

### Additional contract requirements

When a custom path is configured, both the existing GET and POST GraphQL query routes use that URI.
