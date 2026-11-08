Improve cloudflare challenge detection
Since this is based on cloudflare-scrape:

https://github.com/Anorov/cloudflare-scrape/blob/d56c981bfebdb3a53f6437be8c823888c15155d5/cfscrape/__init__.py#L55-L61
```python
    def is_cloudflare_challenge(self, resp):
        return (
            [HIDDEN]
        )
```

However, the status code and headers aren't being checked prior to searching the response body via regex. At very least, this is a performance issue.

### Additional contract requirements

- Response objects expose a boolean `isCloudflare` property. It is `true` when the response status code is greater than 499, the `Server` header starts with "cloudflare" (case-insensitive), and the `Content-Type` header indicates HTML.
- Search a response body for challenge content only after checking the response status and headers. Responses that do not meet the Cloudflare criteria must not be searched for challenge content.
- A Cloudflare response whose body is empty (length less than 1) is reported as a `CloudflareError` that carries the original response object and the HTTP status code.
