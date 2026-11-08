Add the ability to Ignore based on other details, like Transaction Name
## Feature Description
Right now, we're only able to ignore based on URL patterns using the [rules->ignore,](https://docs.newrelic.com/docs/agents/nodejs-agent/installation-configuration/nodejs-agent-configuration/#rules_ignore) config settings or the `NEW_RELIC_IGNORING_RULES` ENV variable. This isn't super helpful when dealing with GraphQL, since the URL is pretty much always the same. We would like to be able to ignore certain requests based on a pattern applied against the `transaction.name` (or open it up to more attributes, but personally we would like `transaction.name`). The reason for this is that we don't want to see Introspection Requests in our APM.

## Describe Alternatives
Another way is that we could just have a config setting `ignoreIntrospection` that we can set to `true` or `false` and pass into the config when creating the plugin:
```typescript
const createPlugin = require('@newrelic/apollo-server-plugin')
const plugin = createPlugin({
  ignoreIntrospection: true
})

// imported from supported module
const server = new ApolloServer({
  typeDefs,
  resolvers,
  plugins: [plugin]
})
```

## Priority
Really Want

### Additional contract requirements

- `createPlugin(instrumentationApi, config = {})` accepts an optional boolean configuration property named `captureIntrospectionQueries`. When the property is omitted its value defaults to `true`.
- An introspection query is a GraphQL operation whose top-level selections are only `__schema` or `__type`.
- When `captureIntrospectionQueries` is `false`, running an introspection query must cause the request's transaction to be ignored: when the transaction finishes, its `ignore` property is `true`.
- When `captureIntrospectionQueries` is `true` (including when the property is omitted), introspection queries are captured normally and their transactions are not ignored by this feature.
- Operations that are not introspection queries are never ignored by this feature, regardless of the value of `captureIntrospectionQueries`.
