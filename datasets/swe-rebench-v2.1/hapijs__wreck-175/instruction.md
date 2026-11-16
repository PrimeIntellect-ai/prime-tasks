Return full response with the Boom HTTP error
With v12, the shortcut methods call back with a Boom error upon HTTP error. This makes it easier to handle HTTP errors when you want to treat them as errors, but it makes it trickier to handle them when you consider them a part of your daily life.

Would there be an objections, if the Boom error included the full `response` object here: https://github.com/hapijs/wreck/blob/master/lib/index.js#L525-L527?

This would allow code like this:
```
cb = (err, response, payload) => {

    if (err) {
       if (!err.data || !err.data.isResponseError) {
           return next(err);
       }
       response = err.data.response;
       payload = err.data.payload;
    }

    // proceed with checks for response.statusCode, etc
}
```

At the moment to handle the 2xx, 3xx and 4xx+ one needs to make checks twice - in the `err` handling code and in the rest of the code. I'm not certain if I'll go ahead with the pattern above, but regardless of that - having the full `response`, rather than just the `headers` might be useful. It would also expose the `statusCode` in a more reasonable location, which at the moment is only included as part of `err.output` (created by Boom?)

I'd probably also include `statusCode` in the "Response Error" message.

### Additional contract requirements

- The Boom error returned for an HTTP error response exposes the full response object as `err.data.response`; it is the `http.IncomingMessage` for the request, so `err.data.response.statusCode` is the numeric HTTP status code.
- The Boom error message for an HTTP error response is `Response Error: <statusCode> <statusMessage>` (for example, `Response Error: 400 Bad Request`).
