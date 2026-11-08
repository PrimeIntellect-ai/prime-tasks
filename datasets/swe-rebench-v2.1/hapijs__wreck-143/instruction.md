Suggestion: Allow json objects as payload
Wreck supports strings, buffers and streams as payload when doing a post/put/patch. I would suggest adding support for JSON objects, just because it would be beautiful to be able to write

`Wreck.post("/endpoint", {payload: {"some":"data"}}, callback)`

Maybe implemented by [HIDDEN] (which would include arrays as well) and set the application/json header.

Just an idea.

### Additional contract requirements

- Accept JSON object and array payloads for POST, PUT, and PATCH requests.
- When no content type is supplied, use `application/json` for a JSON payload; preserve a content type supplied by the caller.
- When a JSON payload is sent with `headers['content-type']` set to `application/json-patch+json`, the request must retain `application/json-patch+json` as its content-type rather than replacing it with `application/json`.
- The request body for a JSON object or array payload must be exactly the compact string produced by `JSON.stringify(payload)`.
