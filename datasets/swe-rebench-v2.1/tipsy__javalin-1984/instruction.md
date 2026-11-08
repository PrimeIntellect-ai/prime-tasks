Provide a possibility to decide if `before` & `after` handlers should be called for non-existing http routes
This issue was kinda referenced on Discord in our latest discussion about `AccessManager`, but I'm reporting this here as there was a fair point about how before/after handlers are used by users. Assuming that users have several routes like:

```
get
post
put
get
// [...] etc. 50 times
```

And they want to register one `before` handler that will be executed before each of those requests, they have two options:

1. Register `before` for each route
2. Use wildcard `*` to catch them all  // I think most users will use this even tho they want to achieve functionality of 1.

The issue with wildcard here is that it'll be also executed for non-existing http routes by default, and it might be slightly confusing for some users (I guess some of them are simply unaware of this behavior). I think it'd be a good idea to provide a possibility to specify matching policy in Javlain 6.x.

### Additional contract requirements

- Provide a way for before handlers to run only when a request matches an existing HTTP route, rather than an unmatched route. Expose it as `beforeMatched(handler)` on the app, taking a handler like `before(handler)`.
- Provide a way for after handlers to run only when a request matches an existing HTTP route, rather than an unmatched route. Expose it as `afterMatched(handler)` on the app, taking a handler like `after(handler)`.
- Ordinary wildcard before and after handlers continue to run on unmatched HTTP requests unless the matching-only behavior is selected.
- The default response body for a request that does not match a route is exactly `Not Found` before any registered after handler modifies it.
