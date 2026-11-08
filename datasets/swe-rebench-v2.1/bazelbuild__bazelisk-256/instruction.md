Add HTTP request retries where they make sense
Just noticed this error in one of our CI logs:

> 2021/07/13 04:26:30 could not resolve the version 'latest' to an actual version number: unable to determine latest version: could not list available releases for 4.1.0: could not list GCS objects at https://www.googleapis.com/storage/v1/b/bazel/o?delimiter=/&prefix=4.1.0/release/: unexpected status code while reading https://www.googleapis.com/storage/v1/b/bazel/o?delimiter=/&prefix=4.1.0/release/: 503

Looks like GCS responded with HTTP 503 Service Unavailable, which suggests that the request should be retried: "Common causes are a server that is down for maintenance or that is overloaded. This response should be used for temporary conditions and the Retry-After HTTP header should, if possible, contain the estimated time for the recovery of the service." (https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/503)

### Additional contract requirements

The retry mechanism must satisfy the following observable behaviour:

- A response with HTTP status 429 or with a status in the range 500-504 (inclusive) is treated as a transient failure and is retried. Any other status (for example 404) is permanent and is not retried.
- When a transient response carries one of the headers `Retry-After`, `X-RateLimit-Reset` or `Rate-Limit-Reset`, the wait before the next attempt is taken from that header. The header value is either a whole number of seconds or an HTTP date (as parsed by `http.ParseTime`).
- When none of those headers is present, the delay before the n-th retry (n starting at 0) is `2^n` seconds plus a random amount between 0 and 500 milliseconds.
- At most `MaxRetries` retries are attempted (default 4).
- The total time spent on a request and its retries does not exceed `MaxRequestDuration` (default 10 seconds).
- If the retry budget is exhausted, `ReadRemoteFile` returns an error whose message is `could not fetch <url>: unable to complete request to <url> after <MaxRetries> retries. Most recent status: <lastStatus>`.
- If the deadline is exceeded, `ReadRemoteFile` returns an error whose message is `could not fetch <url>: unable to complete request to <url> within <MaxRequestDuration>`.
- A permanent (non-retryable) status produces the error `unexpected status code while reading <url>: <status>`.
