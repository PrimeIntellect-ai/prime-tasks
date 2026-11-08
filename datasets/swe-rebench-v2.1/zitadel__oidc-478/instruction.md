Allow custom forwarded header
We have issues at zitadel to use the Forwarded header in production, because our hoster Vercel corrupts the header on the outgoing proxies request.

As a workaround we want to support also x-zitadel-forwarded in the same format as the current forwarded header.

### Additional contract requirements

- In package `pkg/op`, issuer resolution from forwarded headers must be configurable through options: `IssuerFromForwardedOrHost(path string, opts ...IssuerFromOption) func(bool) (IssuerFromRequest, error)`.
- `IssuerFromOption` is the option type accepted by `IssuerFromForwardedOrHost`.
- `WithIssuerFromCustomHeaders(headers ...string) IssuerFromOption` returns an option that makes issuer extraction consider the given header names as forwarded-header equivalents, in the same format as the `Forwarded` header. Every supplied header name is considered, in the order given, and header names are matched case-insensitively. The first configured header that yields a host determines the issuer.
- When both a configured custom header and the `Forwarded` header provide a valid host, the configured custom header takes precedence.
- When a configured forwarded-type header provides a host, the issuer is composed from that host and the supplied path. When none of the configured headers yields a host, the request's `Host` is used and the supplied path is appended.
