Can't read redirected URI
The current API doesn't allow a user to know which URI that the request might have been redirected to. I need the redirected URI to resolve relative links from the redirected resource.

Another complication, is that I would like to be able to `abort()` the request at any time. The redirection logic means that the `ClientRequest` object returned from `Wreck.request()` will stop working this way once the first redirect is active.

The only simple solution, that can solve both of these issues, is to expose a `redirect` callback, which is called whenever a redirect request has been performed. A signature like this should do the trick: `function (status, location, req) {}`.

Let me know if you agree, and I will take a stab at implementing this.

### Additional contract requirements

- Configure the per-redirect callback through the `redirected` request option.
