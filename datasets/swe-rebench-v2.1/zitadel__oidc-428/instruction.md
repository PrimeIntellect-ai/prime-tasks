callback always returns state param, even if empty
As described in the title the `state` query param is always set in the callback url, e.g. `...&state=` which might lead to errors in the client:
https://discord.com/channels/927474939156643850/1121191124493680640

### Additional contract requirements

- The authorization code response is written by the public function `AuthResponseCode(w http.ResponseWriter, r *http.Request, authReq AuthRequest, authorizer Authorizer)` in package `pkg/op`.
- `AuthRequest` is an interface in package `pkg/op` exposing at least `GetState() string`, `GetRedirectURI() string`, `GetResponseType() string` and `GetResponseMode() string`.
- `Authorizer` is an interface in package `pkg/op` exposing `Storage() Storage`, `Crypto() Crypto` and `Encoder() Encoder`.
- `Crypto` is an interface in package `pkg/op` exposing `Encrypt(s string) (string, error)` and `Decrypt(s string) (string, error)`.
- The callback Location serializes `code` before `state`. For a redirect URI of `/auth/callback/`, a code of `id1` and a state of `state1`, the Location is exactly `/auth/callback/?code=id1&state=state1`; when the state is empty the Location is exactly `/auth/callback/?code=id1`.
