Proposal: Graphql Schema replacement
Hey, everyone
Does `fastify-gql` have method for replacing existing graphql schema with another one?

I'm using a microservice architecture with graphql and in some cases, I need to setup schema's autorefresh. (I'm using simple recursive setTimeout)

Example of code for Apollo-Server

```js
const refreshSchema = async () => {
	try {
		const schemaDerivedData = await graphqlServer.schemaDerivedData;

		graphqlServer.schemaDerivedData = Promise.resolve({
			...schemaDerivedData,
			schema: await generateSchema(),
		});
	} catch (err) {
		logger.warn(err, {
			method: 'server.initializeApplication::refreshSchema',
		});
	}

	setTimeout(refreshSchema, config.refreshTimeout);
};

setTimeout(refreshSchema, config.refreshTimeout);
```

Could I somehow replace the existing graphql schema with a new one?

# Implementation

```js
  [HIDDEN]
    [HIDDEN]
  }

```

### Additional contract requirements

- The method is exposed as `app.graphql.replaceSchema(schema)`.
- `replaceSchema` replaces the schema currently used by `app.graphql`, including its resolvers, so that subsequent GraphQL requests are executed against the new schema.
- Calling `replaceSchema` without an argument, or with an argument that is not an object, throws an `Error` with the message `Must provide valid Document AST`.
- Replacing the schema takes effect for every subsequent request: previously cached queries are re-evaluated against the new schema.
