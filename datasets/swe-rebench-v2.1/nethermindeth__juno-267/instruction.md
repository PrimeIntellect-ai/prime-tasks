Reduce overall testing time of juno through changes in REST tests
Tests currently take a long time because the rest api tests which are meant to fail (within /pkg/rest/tests/rest_test.go) take a long time to timeout.

This means that, while the rest of the test suite finishes in less than 10 seconds, all the Test(...)Fail take ~ 10s each, 13 times, incrementing this substantially and wasting time.

It would be good to have 1 timeout test with the normal rate, and the other failing tests to have a much smaller timeout or use a different method to check for failure than to wait out the full 10s.

### Additional contract requirements

- The feeder package must provide a constructor `NewClientWithRetryFuncForDoReq(baseURL string, baseAPI string, client *HttpClient, retryFunc func(req *http.Request, httpClient HttpClient, err error) (*http.Response, error)) *Client`. It behaves like `NewClient` with the same arguments, except that when a feeder request fails, `retryFunc` is called with the original request, the HTTP client, and the error, and its result is used in place of the default retry behavior.
- `NewClient` keeps its existing default retry behavior unchanged.
- When a REST handler's feeder request fails, the handler responds with status 400 and a body that includes the feeder's error message.
