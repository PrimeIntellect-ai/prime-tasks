return an ID token with Device Authorizaiton
Although Device Authorization is an Oauth2-only extension (there is no mention in the OIDC standard) it would be useful if we return an ID Token is the requested scope is set to `openid`. This is to have a compatible result with the rest of the toolkit, regardless of the method of authentication flow that is choosen.

## Acceptance criteria

- [ ] When scope `openid` is set, an ID Token to be returned to the device.
