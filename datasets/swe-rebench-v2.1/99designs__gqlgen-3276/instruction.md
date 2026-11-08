Getting "transport not supported" errors after updating to v0.17.50
Hi.  We recently upgraded from `v0.17.49` to `v0.17.50`, and all requests (queries/mutations) started failing with an error "transport not supported".

After some digging, I discovered the cause.  #3153 added the following to the HTTP POST transport:

https://github.com/99designs/gqlgen/blob/4157ef997ff03647fe4ff9ede27b505fc098932f/graphql/handler/transport/http_post.go#L30-L32

This is a problem because we just use `handler.NewDefaultServer`, which does not set up the SSE transport by default.  Even if I add it with `srv.AddTransport(transport.SSE{})`, it still doesn't solve the problem because that would only be for subscriptions, not regular queries and mutations.

I was also surprised as for why the `Accept` header had `text/event-stream` for a non-subscription request in the first place.  Turns out it was coming from our use of the popular `urql` client library, which does support GraphQL-SSE.  And also, it has this header hardcoded for every request:

https://github.com/urql-graphql/urql/blob/b9f34fd19ee5f9022db4d2f9eb610943c787dac1/packages/core/src/internal/fetchOptions.ts#L149-L154

```ts
const headers: HeadersInit = {
    accept:
      operation.kind === 'subscription'
        ? 'text/event-stream, multipart/mixed'
        : 'application/graphql-response+json, application/graphql+json, application/json, text/event-stream, multipart/mixed',
  };
```

That might be in error - I'm not sure (I reported here: https://github.com/urql-graphql/urql/issues/3673).  But nonetheless, urql has > 1M downloads weekly - so this is bound to affect a lot of people.

From a general HTTP point of view though, the `Accept` header is there to communicate which content types that the client is able to understand, and indeed urql does understand SSE.   IMHO, the presence of `text/event-stream` in the accept header shouldn't mean that the request _can't_ be served by HTTP POST.

As a suggested fix, the SSE transport, if registered, would be used for subscription operations.  Otherwise the normal list of transports should work as they would otherwise.  [HIDDEN]
