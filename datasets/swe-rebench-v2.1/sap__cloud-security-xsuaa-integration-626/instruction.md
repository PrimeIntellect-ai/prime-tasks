Add token_type in OAuth2TokenResponse
Hi Colleagues,

We are trying to use the XSUAA Token Client and Token Flow API for token retrieval.

However, there is one little problem.

If we look at OAuth2TokenResponse we can see that it contains the access token and its expiration time, but it doesn't contain the token type.

Could you please add it to the OAuth2TokenResponse so that there won't be need to use a hard-coded "Bearer " string in our code?

Best regards,
Tsvetomir Lyubenov

### Additional contract requirements

- `OAuth2TokenResponse` in package `com.sap.cloud.security.xsuaa.client` exposes a public constructor `OAuth2TokenResponse(String accessToken, long expiredInSeconds, String refreshToken, String tokenType)` that carries the supplied token type.
- `OAuth2TokenResponse` exposes a public method `String getTokenType()` that returns the token type of the response. When no token type is supplied (the existing three-argument constructor), it returns `"bearer"`.
- `OAuth2TokenServiceConstants.TOKEN_TYPE` is a public constant whose value is `"token_type"`.
- When a token endpoint response contains the field named by `OAuth2TokenServiceConstants.TOKEN_TYPE`, the token type of the resulting `OAuth2TokenResponse` is that field's value.
