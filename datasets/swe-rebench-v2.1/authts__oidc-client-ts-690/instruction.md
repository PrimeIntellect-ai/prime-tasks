User profile information is lost when refresh token is used.
Hi!

I've run into an issue where the profile object on my User is empty after the refresh token is used to get a new access token. It looks like useRefreshToken in the client generates an empty SigninResponse and merges in the new access and refresh tokens to that object. That causes an empty profile to get returned when the new User object is created. [HIDDEN] Or am I just doing something incorrectly. Thanks for the help!
