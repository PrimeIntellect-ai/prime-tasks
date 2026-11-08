Missing state on Login Redirect
I'm not sure whether this is a bug or I do something wrong, however, I would like to read the state that is preserved between the initial load, redirect to IS and redirect back.

From the client and IS point of view, everything seems to be fine, the state is being sent all the way through and comes back as expected:

<i>https://<span></span>localhost:44302/connect/authorize?client_id=MyClient&redirect_uri=http://<span></span>localhost:3000/authentication/login-callback&response_type=code&scope=openid profile offline_access&state=**b5924d628ef74c9b8d599a76d7127cd4**&code_challenge=asX_clrphzIXLga3cj7z3gZofVFz-FXxcer25rVsz4k&code_challenge_method=S256&response_mode=query

https://<span></span>localhost:44302/Account/Login?ReturnUrl=/connect/authorize/callback?client_id=MyClient&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauthentication%2Flogin-callback&response_type=code&scope=openid%20profile%20offline_access&state=**b5924d628ef74c9b8d599a76d7127cd4**&code_challenge=asX_clrphzIXLga3cj7z3gZofVFz-FXxcer25rVsz4k&code_challenge_method=S256&response_mode=query

https://<span></span>localhost:44302/connect/authorize/callback?client_id=MyClient&redirect_uri=http://<span></span>localhost:3000/authentication/login-callback&response_type=code&scope=openid profile offline_access&state=**b5924d628ef74c9b8d599a76d7127cd4**&code_challenge=asX_clrphzIXLga3cj7z3gZofVFz-FXxcer25rVsz4k&code_challenge_method=S256&response_mode=query

http://<span></span>localhost:3000/authentication/login-callback?code=30B4D78B1A42018F8AD3C0579B72A876CFD60936D02998F029BBDBEE3570BED1&scope=openid profile offline_access&state=**b5924d628ef74c9b8d599a76d7127cd4**&session_state=L_rI2q6PV9a_Kljbx5mHL29ftlwEdNQn6k9ky8wak98.3DF5BF2643218A919507CC884F1F1A92</i>

However, if you then look into the storage (I'm using Session storage, but should not make any difference in this case), there is no state with the round-tripped id. I'm using reference tokens and thus I can't read values from tokens as an alternative solution.

Interesting enough, all this works well on sign out redirect. The state id is sent there and back and I can pick up the state from the storage after the final redirect. The issue is not new in `oidc-client-ts`, I've had the same problem with the `oidc-client-js`.

I'm just wondering whether I do something wrong or whether this is an issue of the library.

### Additional contract requirements

A caller must be able to supply a string as `url_state` when starting a sign-in request and retrieve that same string as `url_state` from the sign-in callback response. The callback response must continue to expose the library-generated correlation value as `state`; the caller-supplied value must not replace it.
