Missing call to invalidate remember browser
**Please do not report security vulnerabilities here**. The [Responsible Disclosure Program](https://auth0.com/whitehat) details the procedure for disclosing security issues.

**Thank you in advance for helping us to improve this library!** Your attention to detail here is greatly appreciated and will help us respond as quickly as possible. For general support or usage questions, use the [Auth0 Community](https://community.auth0.com/) or [Auth0 Support](https://support.auth0.com/). Finally, to avoid duplicates, please search existing Issues before submitting one here.

By submitting an Issue to this repository, you agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Describe the problem you'd like to have solved

I'm missing the call to https://auth0.com/docs/api/management/v2#!/Users/post_invalidate_remember_browser

### Describe the ideal solution

An API call to invalidate remember browser

## Alternatives and current work-arounds

Not use node-auth0 to do the call.

### Additional context

N/A

### Additional contract requirements

- Expose the operation on the users manager as `UsersManager.invalidateRememberBrowser`.
