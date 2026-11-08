Support dynamically generating headers for each client request
I would like to use the headers for token-based authentication, e.g. oAuth2. In this case, tokens may expire and need to be refreshed.

However, opamp-go currently only allows specifying a fixed set of headers in the start settings for the client.

Instead, it would be useful to provide a function that can dynamically determine headers, so that tokens could be refreshed for authentication, e.g.:

```go
// StartSettings defines the parameters for starting the OpAMP Client.
type StartSettings struct {
  // Current settings remain unchanged ...

  HeaderFunc func(base http.Header) http.Header
}
```

Here, HeaderFunc is a function that takes in the "base" static headers, and outputs a set of new headers. This would be called on every request sent to the server, and would allow for dynamic authentication headers in case of token refresh, for instance.
