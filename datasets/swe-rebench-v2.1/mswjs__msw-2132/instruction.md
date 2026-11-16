Unable to use HttpResponse.error() with TypeScript
### Prerequisites

- [X] I confirm my issue is not in the [opened issues](https://github.com/mswjs/msw/issues)
- [X] I confirm the [Frequently Asked Questions](https://mswjs.io/docs/faq) didn't contain the answer to my issue

### Environment check

- [X] I'm using the [latest](https://github.com/mswjs/msw/releases/latest) `msw` version
- [X] I'm using Node.js version 18 or higher

### Node.js version

v20.12.1

### Reproduction repository

https://codesandbox.io/p/sandbox/friendly-pare-8tkfgz?file=%2Fmocks%2Fhandlers.ts

### Reproduction steps

`npx tsc`

### Current behavior

Adding a `return HttpResponse.error()` results in a TS error:

```
mocks/handlers.ts:10:31 - error TS2345: Argument of type '() => Response' is not assignable to parameter of type 'GraphQLResponseResolver<GraphQLQuery, GraphQLVariables>'.
  Type 'Response' is not assignable to type 'AsyncResponseResolverReturnType<GraphQLResponseBody<GraphQLQuery>>'.
    Property '[bodyType]' is missing in type 'Response' but required in type 'StrictResponse<GraphQLResponseBody<GraphQLQuery>>'.

10   graphql.query('ListMovies', () => {
                                 ~~~~~~~
```

### Expected behavior

No error.
