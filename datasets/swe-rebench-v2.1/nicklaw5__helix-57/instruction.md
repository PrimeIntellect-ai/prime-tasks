How can I use current access token with ValidateToken?
I have an app that runs while I'm streaming, using this library for Twitch integration (thanks!). I'd like to check if the access token is valid before making API calls, since it's quite likely that my token may expire so I can use the refresh token to update it in that case.

How can I get my current access token from the client in order to check if it is valid? Or is there a way to ask the method itself to use the current token rather than a provided one? Is this a feature that would be useful to others?

### Additional contract requirements

- Add a public method `RequestAppAccessToken(scopes []string) (*AppAccessTokenResponse, error)` on `Client` in package `helix` (file `authentication.go`). It performs the OAuth client-credentials flow and returns the app access token response, or an error on failure.
- Add a public method `RequestUserAccessToken(code string) (*UserAccessTokenResponse, error)` on `Client` in package `helix` (file `authentication.go`). It exchanges an authorization code for a user access token and returns the response, or an error on failure.
- Add a public method `GetAppAccessToken() string` on `Client` in package `helix` (file `helix.go`). It returns the app access token set via `SetAppAccessToken`, or the empty string when no app access token has been set.
- Add a public method `GetUserAccessToken() string` on `Client` in package `helix` (file `helix.go`). It returns the user access token set via `SetUserAccessToken`, or the empty string when no user access token has been set.
