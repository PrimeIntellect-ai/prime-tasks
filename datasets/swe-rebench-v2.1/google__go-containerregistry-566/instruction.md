Implement password grant_type for oauth
For [the oauth flow](https://docs.docker.com/registry/spec/auth/oauth/), we currently just pass through IdentityToken if it's set. In order to fix azure support, I believe we also need to implement the username/password flow for oauth.
