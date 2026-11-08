Allow URLs with paths as base_url in ClientSession
### Is your feature request related to a problem?

Many sites have an API path in the URL. For example, Jira uses {jira_url}/rest/api/2/ as the base for its API requests.
The current implementation of the ClientSession only allows absolute URLs without a path. Thus, to make a number of Jira requests, you would do something like:
```python
async with aiohttp.ClientSession(base_url="https://jira.com") as client:
    baz = await client.get("/rest/api/2/issue/ISSUE-1")
    bom = await client.get("/rest/api/2/project/ISSUE")
```
instead of the simpler
```python
async with aiohttp.ClientSession(base_url="https://jira.com/rest/api/2") as client:
    baz = await client.get("/issue/ISSUE-1")
    bom = await client.get("/project/ISSUE")
```

This somewhat defeats the purpose of having the base_url in the first place.

### Describe the solution you'd like

Allow using paths in the base_url, similar to how Requests and HTTPX do.

### Describe alternatives you've considered

Just continue typing in the path or using variables with f-strings.

### Related component

Client

### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- `base_url` must be an absolute URL. If it has a path, that path must end
  with a trailing `/`; otherwise `ClientSession` raises `ValueError` with the
  message `base_url must have a trailing '/'`.
- URL joining follows RFC 3986. A request URL that begins with `/` is
  resolved from the root of the base URL's authority, so it discards the base
  URL's path: joining base `http://example.com/test1/` with `/test2` yields
  `http://example.com/test2`. A request URL that does not begin with `/` is
  joined to the base URL's path: joining base `http://example.com/test1/` with
  `test2` yields `http://example.com/test1/test2`.
