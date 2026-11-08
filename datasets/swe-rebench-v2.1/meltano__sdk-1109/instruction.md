[Feature]: Allow built-in request authentication helpers to be used
### Feature scope

Taps (catalog, state, stream maps, etc.)

### Description

Some of these are nice, and would at least remove from duplication on our side:

- [requests.auth.HTTPBasicAuth(username, password)](https://requests.readthedocs.io/en/latest/_modules/requests/auth/#HTTPBasicAuth)
Attaches HTTP Basic Authentication to the given Request object.

- [requests.auth.HTTPProxyAuth(username, password)](https://requests.readthedocs.io/en/latest/_modules/requests/auth/#HTTPProxyAuth)
Attaches HTTP Proxy Authentication to a given Request object.

- [requests.auth.HTTPDigestAuth(username, password)](https://requests.readthedocs.io/en/latest/_modules/requests/auth/#HTTPDigestAuth)
Attaches HTTP Digest Authentication to the given Request object.

https://requests.readthedocs.io/en/latest/api/#authentication

Custom authenticators are also interesting, and developers would be able to leverage existing auth packages in the wild:

- https://github.com/tedder/requests-aws4auth
- https://github.com/pyauth/requests-http-signature
- https://github.com/Colin-b/requests_auth

https://requests.readthedocs.io/en/latest/user/advanced/#custom-authentication

---

The implementation seems easy enough as we already did most of the work in https://github.com/meltano/sdk/pull/842. [HIDDEN]

[HIDDEN]

[HIDDEN]

[HIDDEN]

### Additional contract requirements

- REST streams must accept any Requests-compatible authentication callable, including custom authenticators supplied by third-party packages, and apply its changes when preparing requests.
- `APIAuthenticatorBase` instances must be usable as Requests authentication callables and apply their SDK authentication to requests prepared by Requests.
