[oauth2] [authorization code] No redirect_uri must result on an error
I did not set a redirect_uri when asking for an auth. code.
Also, my client doesn't have a redirect_uri in his configuration.

This situation must results on an error instead of being redirected to the login form

### Additional contract requirements

- For this case, return HTTP 302 Found with the `Location` header exactly `/test/oauth/error?error=invalid_request&error_description=A+redirect_uri+must+be+supplied.`
