Is there a way to allow all URL schemes?
Basically something like `AllowURLSchemeWithCustomPolicy` but for all schemes.

References:
- https://github.com/go-gitea/gitea/issues/21146
- https://github.com/go-gitea/gitea/issues/16721

### Additional contract requirements

Provide a chainable `Policy.AllowURLSchemesMatching(r *regexp.Regexp) *Policy` method. During sanitization, a URL whose scheme matches `r` must be accepted. This must support accepting URLs with any non-empty scheme by supplying a regexp that matches every scheme.
