ErrorResponse.Error() method can panic if err.Response.Request is nil
First of all thank you so much for this sdk. It is so useful for writing tools/bots using this.

I am trying to implement a new tool using this sdk, and ran into a problem where printing the ErrorResponse is causing 'nil pointer dereference' error.

on trying to debug this, it seems like in following code `r.Response.Request` is nil and therefore resulting in the error:

```
func (r *ErrorResponse) Error() string {
	return fmt.Sprintf("%v %v: %d %v %+v",
		r.Response.Request.Method, sanitizeURL(r.Response.Request.URL),
		r.Response.StatusCode, r.Message, r.Errors)
}

```

[HIDDEN]

FWIW, I was trying to use CreatePullRequest API with a PAT which didn't had enough permissions and therefore getting a `403 forbidden` error.

the json representation of the error is attached for reference:

<details>
  <summary>JSON representation of ErrorResponse</summary>

```
{
  "resp": {
    "Status": "403 Forbidden",
    "StatusCode": 403,
    "Proto": "HTTP/1.1",
    "ProtoMajor": 1,
    "ProtoMinor": 1,
    "Header": {
      "Access-Control-Allow-Origin": [
        "*"
      ],
      "Access-Control-Expose-Headers": [
        "ETag, Link, Location, Retry-After, X-GitHub-OTP, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Used, X-RateLimit-Resource, X-RateLimit-Reset, X-OAuth-Scopes, X-Accepted-OAuth-Scopes, X-Poll-Interval, X-GitHub-Media-Type, X-GitHub-SSO, X-GitHub-Request-Id, Deprecation, Sunset"
      ],
      "Content-Security-Policy": [
        "default-src none"
      ],
      "Content-Type": [
        "application/json; charset=utf-8"
      ],
      "Date": [
        "Mon, 23 Oct 2023 15:50:56 GMT"
      ],
      "Github-Authentication-Token-Expiration": [
        "2024-10-22 00:00:00 +0530"
      ],
      "Referrer-Policy": [
        "origin-when-cross-origin, strict-origin-when-cross-origin"
      ],
      "Server": [
        "GitHub.com"
      ],
      "Strict-Transport-Security": [
        "max-age=31536000; includeSubdomains; preload"
      ],
      "Transfer-Encoding": [
        "chunked"
      ],
      "Vary": [
        "Accept-Encoding, Accept, X-Requested-With"
      ],
      "X-Accepted-Github-Permissions": [
        "pull_requests=write"
      ],
      "X-Content-Type-Options": [
        "nosniff"
      ],
      "X-Frame-Options": [
        "deny"
      ],
      "X-Github-Api-Version-Selected": [
        "2022-11-28"
      ],
      "X-Github-Media-Type": [
        "github.v3; format=json"
      ],
      "X-Github-Request-Id": [
        "C56A:146E27:5D915D:6C0EFE:65369660"
      ],
      "X-Ratelimit-Limit": [
        "5000"
      ],
      "X-Ratelimit-Remaining": [
        "4976"
      ],
      "X-Ratelimit-Reset": [
        "1698079299"
      ],
      "X-Ratelimit-Resource": [
        "core"
      ],
      "X-Ratelimit-Used": [
        "24"
      ],
      "X-Xss-Protection": [
        "0"
      ]
    },
    "Body": {
      "Reader": {}
    },
    "ContentLength": 147,
    "TransferEncoding": null,
    "Close": false,
    "Uncompressed": false,
    "Trailer": null,
    "Request": null,
    "TLS": null
  },
  "message": "Resource not accessible by personal access token",
  "errors": null,
  "documentation_url": "https://docs.github.com/rest/pulls/pulls#create-a-pull-request"
}e
```
</details>

### Additional contract requirements

- Calling `ErrorResponse.Error()` when `Response` is non-nil and `Response.Request` is nil must not panic and must return a non-empty error string.
