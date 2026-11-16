Federated logout
It seems like auth-spa-js 1.1.0 currently does not support telling auth0 to perform a [federated logout](https://auth0.com/docs/logout/guides/logout-idps). There seems to be no way to pass the required _federated_ query parameter since the `LogoutOptions` interface does not allow this:
https://github.com/auth0/auth0-spa-js/blob/5f946338af92183298d93161e9f181b823cd2ec2/src/global.ts#L162-L179

Am i missing something? If not, can you please add an option to support auth0's federated logout?

### Additional contract requirements

`LogoutOptions` must expose an optional boolean property named `federated`. When it is `true`, `auth0.logout` must include the `federated` query parameter in the logout URL. When it is absent or `false`, logout must retain its existing URL behavior without that parameter.
