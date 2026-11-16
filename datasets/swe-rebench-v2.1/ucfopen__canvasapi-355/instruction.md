Add support for GraphQL endpoint
**What endpoints need to be covered?**
[GraphQL](https://canvas.instructure.com/doc/api/file.graphql.html) is a new endpoint that would be nice if it had a way to query it via this API.

Initial implementation would just be to support this endpoint `POST /api/graphql` for making raw JSON POST requests and getting back a dict response. Future enhancements might be to switch over existing calls to optionally use this endpoint rather than going through the Canvas API methods for improved performance.

I'm working on a proof or concept that I could use some review on.

### Additional contract requirements

- Add a public method `Canvas.graphql(self, query, variables=None, **kwargs)` to the `Canvas` class in the `canvasapi.canvas` module. It sends a `POST` request to the Canvas GraphQL endpoint `/api/graphql` and returns the JSON-decoded response body as a `dict`. `query` is the GraphQL query string; `variables` is an optional mapping of variable names to values; any additional keyword arguments are accepted.
- The request body is JSON containing the query under the `query` key and, when `variables` is provided, the variables under the `variables` key.
- Add a public exception class `UnprocessableEntity` in the `canvasapi.exceptions` module. It is raised when Canvas responds with HTTP status 422.
