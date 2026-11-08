[Bug] onResolution hook extensions do nothing.
While trying to add extensions to my GraphQL return data as mentioned in #466, I tried using mercurius `onResoluton` hook to do so, as it has a `exec.extensions` property, but when I get my results back, I don't have any extensions.

What I expect is for there to be extensions data.

A minimum code example:

```ts
import fastify, { FastifyInstance } from 'fastify'
import mercurius from 'mercurius'

const server: FastifyInstance = fastify()

await server.register(mercurius, {
	schema,
	graphiql: true,
})

await server.graphql.addHook('onResolution', async (exec, context) => {
	exec.extensions = {
		test: 'Test Extension',
	}

	await Promise.resolve()
})
```
