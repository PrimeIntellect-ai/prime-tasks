GQL spec compliance for http status codes (200 everywhere)
I've been migrating from Apollo to Mercurius and noticed that queries that return GQL errors have status code 500. This trips up our client code, thinking it's a Network Error instead of an application error.

I took a look at the spec here:
https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#applicationjson

It seems to mention that:

> The server SHOULD NOT use a 4xx or 5xx status code.

> Note: For compatibility with legacy servers, this specification allows the use of 4xx or 5xx status codes for failed requests where the response uses the application/json media type, but it is strongly discouraged. To use 4xx and 5xx status codes, please use the application/graphql-response+json media type

This has already been discussed here: https://github.com/mercurius-js/mercurius/issues/599#issuecomment-940734753

I implemented a custom errorFormatter to address this as mentioned in the documentation.

However, now that the spec recommends `200` everywhere, I think it might make sense to change it in the next Mercurius version accordingly.

### Additional contract requirements

- GraphQL execution errors (errors produced while executing a valid GraphQL document) are returned with HTTP status `200 OK`, whether the response contains data or only errors, and regardless of the number of errors.
- A request whose GraphQL document fails validation is returned with HTTP status `400 Bad Request`.
- When a single GraphQL error carries an explicit `statusCode`, that status code is used instead of `200`.
