Is there a way to generate a url for each request?
I'd like to benchmark `POST` requests where I could pass a random id at the end of path.
I tried using `setupClient` to change the url, but I'll only change the first request of each client.

### Additional contract requirements

A URL path may use `[%3Cid%3E]` as a placeholder for a generated identifier suffix. When ID replacement is enabled, replace the placeholder for each request, so successive POST requests use different identifier suffixes.
