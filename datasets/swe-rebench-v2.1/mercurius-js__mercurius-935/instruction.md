Is there a way to receive query as AST?
Hello!

Before que used to have apollo-graphql-lambda which supports parsing Graphql AST directly. We've migrated to mercurius but some of our clients sends us graphql AST in the query payload. The thing is we had to create a fastify contentTypeParser to transform that AST back to string, but that is not something we want to keep because it doesn't make much sense as the string is converted back to AST by mercurius, so we are adding unnecessary overhead.

Is there a way of processing graphlq AST directly?

### Additional contract requirements

- The plugin adds a public `graphql(source: string)` method to the Fastify instance (available after the plugin is registered). It executes a GraphQL operation against the registered schema and resolves with the execution result (`{ data?, errors? }`).
- `source` may be a standard GraphQL query string or a JSON-encoded GraphQL AST (a valid `DocumentNode`).
- AST input is also accepted through the HTTP `/graphql` endpoint's `query` field.
- When the source is a JSON-encoded AST that is not a valid GraphQL AST, the method throws an error whose message begins with `Invalid AST Node:`.
