Any HTTP Client sending error is logged as status 400 response
https://github.com/fortio/fortio/blob/4a325b93146c7faf5d7ff5a327d3c86abceb141f/fhttp/http_client.go#L377

Why is any HTTP client sending error added in the statistics as a status 400 response?

For instance if I run a test over an http endpoint expecting an httpS endpoint, the client fail negotiating the encryption but all the requests are logged as a status 400 response from the server, hiding the real problem, and also dirtying the statistics.
