Fetch wrapper breaks token for some providers when refreshing
I'm using Cognito as the OAuth provider. In this case, the tokens returned to the client when providing a refresh token do not include a new refresh token (nor the old one - no refresh token comes back at all). This means that https://github.com/badgateway/oauth2-client/blob/dfaa4622ff37217a62a8daa551257c385e8bd7b4/src/client.ts#L184 wipes out the refresh token and subsequent refreshes will fail. I've mentioned the fetch wrapper because that's where I noticed the behaviour, but it appears this will happen for any refresh.

[HIDDEN] I can PR for this if you're happy with the approach.

### Additional contract requirements

- During token refresh, use a newly issued refresh token when the provider response includes one. If the response omits a refresh token, the refresh operation must retain the refresh token supplied to it.
