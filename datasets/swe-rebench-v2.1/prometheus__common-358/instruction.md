Feature request: add support for client-credentials oauth2 authorization using proxy
@roidelapluie  Add support for client-credentials oauth2 authorization using proxy.

### Additional contract requirements

When an `oauth2` configuration specifies a `proxy_url`, the OAuth2 client-credentials
token request must be sent through that HTTP proxy.
