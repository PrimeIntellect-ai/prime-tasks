Cannot put client id into scopes, therefore cannot get access_token for Azure B2C
According to [Azure B2C documentation](https://learn.microsoft.com/en-us/azure/active-directory-b2c/access-tokens#openid-connect-scopes), to get an access_token, client id must be added to scopes, i.e. `scopes=['openid', 'offline_access', '<CLIENT_ID>']`.
> The OpenID Connect standard specifies several special scope values. The following scopes represent the permission to access the user's profile:
> * openid - Requests an ID token.
> * offline_access - Requests a refresh token using [Auth Code flows](https://learn.microsoft.com/en-us/azure/active-directory-b2c/authorization-code-flow).
> * 00000000-0000-0000-0000-000000000000 - Using the client ID as the scope indicates that your app needs an access token that can be used against your own service or web API, represented by the same client ID.

[HIDDEN]

https://github.com/AzureAD/microsoft-authentication-library-for-python/blob/545e856124985da4758530ab811d2c137fa8e333/msal/application.py#L591

### Additional contract requirements

- For a scope list containing the client ID, either alone or with `foo`, the set of resulting scopes must equal the set of supplied scopes plus `openid`, `profile`, and `offline_access`.
