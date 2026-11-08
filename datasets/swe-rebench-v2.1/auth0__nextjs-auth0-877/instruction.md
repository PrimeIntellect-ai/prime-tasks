Support federated params for logout
### Checklist

- [X] I have looked into the [README](https://github.com/auth0/nextjs-auth0#readme) and have not found a suitable solution or answer.
- [X] I have looked into the [examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com/c/sdks/5) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Describe the problem you'd like to have solved

Please add support for https://auth0.com/docs/authenticate/login/logout/log-users-out-of-idps

### Describe the ideal solution

[HIDDEN]

### Alternatives and current workarounds

_No response_

### Additional context

_No response_

### Additional contract requirements

Callers must be able to provide additional query parameters for logout through the `logoutParams` logout option. Those parameters, including `federated`, must be included in the redirect to the identity provider.
