RFC8707 - Possible Missing Multiple Resources handling for Code Flow Authorization Request
Hello,

My question might be totally naive, but here I go:
We have an SSO from which we're gettings Access/Refresh/Id token in order to later call 2 Services.
We're trying to add the `resource` information as part of the AuthCode Grant during signing in order to generate dedicated token(s ?) to hit both ApiOne and ApiTwo. (see image above from the RFC)
[RFC 8707 - Resource Indicators for OAuth 2.0](https://www.rfc-editor.org/rfc/rfc8707.html)
![image](https://user-images.githubusercontent.com/2266487/202176864-d9fc43a8-cc7e-483d-a4b0-07b207d22375.png)

(On refresh the same will apply by sending the last valid refresh token + the appropriate resources)

My question being ... how can this be achieved with the library today for both SignIn, Refresh, etc ...
From the `OidcClient.ts` `resource` seems to be a simple string here:
https://github.com/authts/oidc-client-ts/blob/0e6bfc22ba2181bf52934b1666ac61d9a0a92069/src/OidcClient.ts#L37

and it seems to be forwarded
https://github.com/authts/oidc-client-ts/blob/0e6bfc22ba2181bf52934b1666ac61d9a0a92069/src/OidcClient.ts#L111

And I cannot find the could mapping that to the `&resource=`

### Additional contract requirements

For code-flow authorization requests, callers can request multiple resource indicators through the `resource` option in sign-in request arguments or OIDC client settings. This option accepts either one resource identifier as a string or multiple identifiers as an array of strings. Each supplied identifier is represented by its own `resource` query parameter in the authorization URL, and resource values from client settings are forwarded to the request. The existing single-string form continues to work.
