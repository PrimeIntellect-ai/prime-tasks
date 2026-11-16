‘autoredirect‘ force use 'https'
I'm using nginx to proxy `distribution` and `auth server` in kubernetes, both http and https configured. If i enable `autoredirect`, it always return https location with proxy host, then http port can not be used.


https://github.com/docker/distribution/blob/980d1a696b5c5bed25835f25d06ec2ef3ddc24b0/registry/auth/token/accesscontroller.go#L104

Can we make it smarter? or i disable `autoredirect` to use `realm` option.

### Additional contract requirements

- When `autoredirect` is enabled, the redirect URL scheme is `https` unless the request carries an `X-Forwarded-Proto` header, in which case the header's value is used as the scheme.
- The redirect URL is `<scheme>://<request Host><redirect path>`.
- The token authentication configuration accepts an optional `autoredirectpath` string option that sets the redirect path when `autoredirect` is enabled.
- When `autoredirect` is enabled and `autoredirectpath` is not provided (or is empty), the redirect path defaults to `/auth/token`.
