Don't lose status codes in CompositeAsyncHandler
Current best example is the body parsers. These will throw an error with status code 415 if the media type is not supported, but the composite handler will merge these into an error with status code 400. Perhaps the composite handler should [HIDDEN] (not sure how best to do that yet).

### Additional contract requirements

- When one handler throws an `HttpError` with status code 401 and another throws an ordinary `Error`, `CompositeAsyncHandler` must reject with an error whose `statusCode` is 500 and whose `name` is `InternalServerError`.
- When all handlers fail with the same HTTP status code, `CompositeAsyncHandler` must preserve that status code rather than replacing it with a generic status; unsupported-media-type failures must retain status code 415.
