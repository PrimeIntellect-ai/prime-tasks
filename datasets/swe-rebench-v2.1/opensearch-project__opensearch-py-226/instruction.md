[BUG] additional info missing from TransportError when using async
### What is the bug?
`TransportError`s are missing the parsed json stored on the `info` property when using the library with async.

[HIDDEN]
See the difference between the [sync code](https://github.com/opensearch-project/opensearch-py/blob/8879644ec404b3ab15b739b97775d7bd7e51018b/opensearchpy/connection/http_requests.py#L204-L208) and the [async code](https://github.com/opensearch-project/opensearch-py/blob/8879644ec404b3ab15b739b97775d7bd7e51018b/opensearchpy/_async/http_aiohttp.py#L340)

### How can one reproduce the bug?
Make bad requests (e.g. 400s) when using the async code.

### What is the expected behavior?
`TransportError`s `info` property should contain a dict with the parsed response (as in non-async use of the library).

### What is your host/environment?
Linux + MacOs

### Do you have any screenshots?
Links to code above.

### Do you have any additional context?
This bug was introduced in 1.1.0 when the content-type header started to be inspected before parsing the json. https://github.com/opensearch-project/opensearch-py/commit/1cd15b08453a860624b5c405eed4d4052e916096

### Additional contract requirements

- For an async 400 response with a JSON body containing `{"error": {"type": "snapshot_in_progress_exception"}}`, `TransportError.error` must equal `snapshot_in_progress_exception`.
