Okta OpenID Connect Custom Auth Server Error
### Expected behaviour

When using a custom authorization server, with OktaOpenIdConnect, the proper openid-configuration URL should be generated.

### Actual behaviour

Okta OpenID Connect has two different URLs for the [openid-configuration API](https://developer.okta.com/docs/reference/api/oidc/#well-known-openid-configuration).

* `https://${yourOktaDomain}/.well-known/openid-configuration`
* `https://${yourOktaDomain}/oauth2/${authorizationServerId}/.well-known/openid-configuration`

When using a authorization server the URL generation code truncates off the `oauth2/${authorizationServerId}` resulting in a `404` error when attempting to hit the openid-configuration URL. For the non-custom authorization server use case, the code works fine.

### What are the steps to reproduce this issue?

1. Setup a custom authorization server in Okta for OpenID Connect
2. Set the `SOCIAL_AUTH_OKTA_OPENIDCONNECT_API_URL` variable to your custom server URL
3. Attempt to authenticate through the app.

### Any logs, error output, etc?

I'm using this module through https://github.com/netbox-community/netbox which is currently pinned to version 4.1.0. The behavior I describe in this ticket is actually the opposite, custom-auth servers work and non-custom auth servers break. I wrote this issued based on [this commit](https://github.com/python-social-auth/social-core/commit/5c8f653ed04de0724e55de096a13e0d08da86fc0#diff-0990f86a2ca92170c32636801c9fad59f839302df2d28d822be2c9e76069708c) which sets up the behavior described in this issue.

### Additional contract requirements

During OpenID Connect authentication, the discovery request must use the appropriate Okta endpoint: the Okta domain root for the default authorization server, and the `/oauth2/${authorizationServerId}` path for a custom authorization server.
