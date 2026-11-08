Support Batched Queries
I'd like to submit a PR to implement this. First I wanted to raise the issue and see if you'd be willing to accept a PR or if you had any feedback.

---

We're currently migrating from Apollo Server to Fastify GQL because of the performance benefits.

Our mobile app makes use of [apollo-link-batch-http](https://www.apollographql.com/docs/link/links/batch-http/) for performance. This batches GraphQL queries which are run within a configurable interval. The request issued is an array of query objects, rather than a singular query object.

In order to support this, the graphql server must be able to merge the query objects and variables prior to the executing the query as per usual.

In order to support this in Fastify GQL:
- [x] Update schema to allow array or object.
- [x] Update handler to merge GraphQL queries if an array is provided.
- [x] Test with batched queries
- [x] Test with normal queries

### Additional contract requirements

- The plugin accepts an `allowBatchedQueries` boolean option when registered via `app.register(GQL, options)`.
- When `allowBatchedQueries` is `true` and the POST request body sent to the `/graphql` endpoint is an array of query objects, the endpoint responds with an array of GraphQL response objects, one per query, in request order.
- When `allowBatchedQueries` is not `true`, an array request body is not batched and the endpoint returns a single response object as before.
- For a batched request, an item whose query is malformed produces `{ errors: [{ message: 'Bad Request' }] }` for that item.
- For a batched request, an item whose resolver throws produces `{ errors: [{ message: 'Internal Server Error' }] }` for that item.
