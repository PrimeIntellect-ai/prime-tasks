Bug: Logout does not log out on auth provider
<!--
  Please provide a clear and concise description of what the bug is. Include
  screenshots if needed. Please test using the latest version
-->

## Steps To Reproduce

1. setup logoutEndpoint
2. use logOut()
3. watch storage being cleared
4. login()
5. Doesn't redirect to authprovider/login and auto logs in

## The current behavior

Currently doesn't "log out", only clears client side info but doesn't redirect to logout endpoint.

## The expected behavior

Should log out on server and client.
