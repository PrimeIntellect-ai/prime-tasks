GraphQL response content-type header assertion failing
Love your library design BTW.

Small issue I thought I would call out. I'm using Github enterprise server 2.19.7 and the `content-type` header on the response to the `/api/graphql` request is different than the rest api. By one space to be exact.

There's an assertion on line 242 that expects the content type to equal `application/json; charset=utf-8`, and it does in response a v3 rest api call, but the v4 graphql api returns `application/json;charset=utf-8`.

https://github.com/brettcannon/gidgethub/blob/48db737541537d0df78dac2cfac717e86d158e7a/gidgethub/abc.py#L242

It's easy enough to work around (because your library is awesome), I'm just doing this for now:

```python
class MyGitHubAPI(GitHubAPI):
    async def _request(
        self, method: str, url: str, headers: Mapping[str, str], body: bytes = b""
    ) -> Tuple[int, Mapping[str, str], bytes]:
        # Add proxy auth token
        headers = dict(**headers, **generate_proxy_header())
        # return await super(MyGitHubAPI, self)._request(method, url, headers, body)
        resp_status, resp_headers, resp_data = await super(MyGitHubAPI, self)._request(
            method, url, headers, body
        )
        resp_headers = dict(resp_headers)
        resp_headers["content-type"] = "application/json; charset=utf-8"
        return resp_status, resp_headers, resp_data
```

### Additional contract requirements

- The `gidgethub` package exposes a public exception class `GraphQLResponseTypeError` that inherits from `GraphQLException`.
- `GitHubAPI.graphql` raises `GraphQLResponseTypeError` when the response's `Content-Type` is not `application/json`, including when the header is missing or empty.
- The `GraphQLResponseTypeError` message includes the unexpected content type, and its `response` attribute holds the decoded response body as a string.
