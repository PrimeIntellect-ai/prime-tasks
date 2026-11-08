Lib failing to retrying on 5xx if it can't parse the body
[Customer using ably-go 1.1.2](https://support.ably.io/a/tickets/106111) reporting 400 errors. On investigation this was due to cloudfront returning rendered HTML for 502 errors; ably-go is then unable to parse the body, and turns it into a 400 error.

But this is incorrect - the library should be retrying for any response with an http status code 500-504 (specific spec violation: https://docs.ably.io/client-lib-development-guide/features/#RSC15d), doesn't matter what the body is. It still has the HTTP status code, and can decide to retry based on that.

Possibly introduced by https://github.com/ably/ably-go/pull/129/files (though that may have been fixing even-more-broken older behaviour)

### Additional contract requirements

- If a response has `Content-Type: text/html` and HTTP status 405, the returned `*ably.Error` must have `StatusCode` equal to 405.
