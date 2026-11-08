Bug in auto_referer implementation
When `isahc` is asked to follow redirects with [auto_referer](https://docs.rs/isahc/latest/isahc/config/trait.Configurable.html#method.auto_referer) enabled, it will add a `Referer` header to subsequent requests after being redirected. However, the current implementation does not remove previous `Referer` headers. Therefore, the final request will have multiple `Referer` headers if it is redirected more than once. This is different from `curl --location --referer ";auto"` which only retains the last `Referer` header. I think this is a bug and should be fixed.
https://github.com/sagebind/isahc/blob/2a5c1754f7b92e9b5c8b7e0f203819bd93c23697/src/redirect.rs#L83-L87

By the way, the current implementation also does not remove the fragment and userinfo components of the URI, a `MUST NOT` requirement in [RFC 7231](https://httpwg.org/specs/rfc7231.html#header.referer). `curl` conforms to the RFC, and it would be nice if `isach` does as well.
