Inconsistent error output on SSR rehydration
## Description

1\) 404 cases lead to different SSR and Browser representations of `error`.
2\) SSR representation seems to be slightly off.

### Steps to reproduce

1) Access 404 API from Browser directly (trigger SSR).
2) Access 404 API from Browser via link (trigger client fetching).

By 404 API I mean any API returning `message: "Not Found", code: INTERNAL_SERVER_ERROR` which is probably not perfect but is the default ApolloServer behavior:

> AuthenticationError — for authentication failures
> ForbiddenError — for authorization failures
> UserInputError — for validation errors on user input
> **As a fallback for uncaught failures, any other unknown errors thrown within your resolver will add the code INTERNAL_SERVER_ERROR**
> https://blog.apollographql.com/full-stack-error-handling-with-graphql-apollo-5c12da407210

and shouldn't really matter for the context of this issue.

### Code

```
// some NextJS page

let [dataResult] = useQuery({
  query,
})

if (dataResult.error) {
  console.log(dataResult.error) // !!!
  return <Error message={dataResult.error.toString()}/>
}
```

### SSR Error

```
[CombinedError: [Network] undefined] {
  name: 'CombinedError',
  message: '[Network] undefined',
  graphQLErrors: [
    GraphQLError: Not Found
        at rehydrateGraphQlError (/.../node_modules/urql/dist/cjs/index-dddbd19e.js:23:12)
        at Array.map (<anonymous>)
        at new CombinedError (/.../node_modules/urql/dist/cjs/index-dddbd19e.js:39:61)
        ...
        at b (/.../node_modules/wonka/dist/wonka.js:865:14)
        at Array.forEach (<anonymous>) {
      message: 'Not Found'
    }
  ],
  networkError: Error: undefined
      at /.../node_modules/urql/dist/cjs/core.js:525:25
      ...
      at d (/.../node_modules/wonka/dist/wonka.js:137:16),
  response: undefined
}
```

`error.toString()` currently produces (at server) `[Network] undefined`.
Somehow it misses the informative ` GraphQLError: Not Found` part and goes for the weird  `[Network] undefined`

### Browser

Talking about the same error in Browser.

`error.toString()` currently produces `[GraphQL] Not Found`.
Which LGTM.

---

The same error should probably lead to the same structures in Browser and Server.
At least, the error in Server should be improved to match the Browser one.
Stacktraces will be different for sure, but the final messages of `toString` should match IMO.

### Additional contract requirements

- When a cached result contains a network error, SSR rehydration must preserve it as a network error and retain its informative message; the rehydrated error's `toString()` must include that message.
