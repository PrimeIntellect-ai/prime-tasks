getTokenSilently takes `timeout` options instead of `timeoutInSeconds`
Hello! We've bumped into a nasty bug where `timeoutInSeconds` options passed into `getTokenSilently`is ignored and couldn't figure out where the issue is. Upon inspecting library's code we were able to identify that the `timeoutInSeconds` is not used at all in [HIDDEN] which is called eventually in `getTokenSilently`.

Instead [`customOptions`](https://github.com/auth0/auth0-spa-js/blob/5959a2c3f262aec98613964b21975324f440515b/src/Auth0Client.ts#L883) [HIDDEN] [`oauthToken`](https://github.com/auth0/auth0-spa-js/blob/5959a2c3f2/src/utils.ts#L361) [HIDDEN]

This is especially confusing since docs doesn't mention `timeout` option at all https://auth0.github.io/auth0-spa-js/interfaces/gettokensilentlyoptions.html

### Additional contract requirements

- When `getTokenSilently` receives `timeoutInSeconds`, a refresh-token request must honor the corresponding timeout duration, converted from seconds to milliseconds, rather than ignoring the option.
