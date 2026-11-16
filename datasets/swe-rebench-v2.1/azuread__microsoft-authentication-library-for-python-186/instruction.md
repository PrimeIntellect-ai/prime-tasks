Refresh token errors are discarded
`acquire_token_silent_with_error` appears to be intended to return the last error response received from AAD, and the documentation implies it does so, but there are cases in which it does not.

For example, if AAD rejects a refresh token, its error response is discarded (`at` is the response):
https://github.com/AzureAD/microsoft-authentication-library-for-python/blob/5c1f0f4ad18a61587393c290b1094b5f8fd014d4/msal/application.py#L601-L609

When AAD rejected the token, that token was evicted from the cache:
https://github.com/AzureAD/microsoft-authentication-library-for-python/blob/5c1f0f4ad18a61587393c290b1094b5f8fd014d4/msal/oauth2cli/oauth2.py#L449-L450

[HIDDEN]

This behavior arguably makes sense because the difference between "no refresh token in the cache" and "only invalid refresh tokens in the cache" may not be interesting. But the documentation on `acquire_token_silent_with_error` implies it will distinguish these cases, so I describe the inconsistency here for comment and clarification.

### Additional contract requirements

If AAD rejects a cached refresh token and no refresh token is available for subsequent cache lookups, `acquire_token_silent_with_error` must return the rejected AAD error response rather than `None`. A cache miss without a rejected refresh-token response may still return `None`.
