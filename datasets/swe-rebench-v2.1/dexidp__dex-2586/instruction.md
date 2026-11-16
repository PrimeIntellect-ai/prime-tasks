Microsoft Connector adds extra interactive step in login for tenants with known domains
### Preflight Checklist

- [X] I agree to follow the [Code of Conduct](https://github.com/dexidp/dex/blob/master/.github/CODE_OF_CONDUCT.md) that this project adheres to.
- [X] I have searched the [issue tracker](https://www.github.com/dexidp/dex/issues) for an issue that matches the one I want to file, without success.

### Problem Description

When a user with multiple Microsoft sessions uses the Microsoft connector in Dex, the `/authorize` page displays an interactive UI rather than a seamless redirect.  The page with title "Pick an account" allows the user to select from a list of accounts known to Microsoft.

<img width="481" alt="PickAnAccount-censored" src="https://user-images.githubusercontent.com/10874210/177431402-de9673e5-8a62-46f3-8c84-938cabaca06d.png">

This account list contains a mix of tenant and personal accounts, including accounts without current sessions.
Upon selecting an account, the authentication proceeds normally.

In cases where the specific `tenant` parameter is configured for the Microsoft connector, the administrator is intentionally restricting access to users in the specified tenant.  Should a user select an account outside of the tenant on the "Select an account" page, the request will be rejected within Microsoft's OAuth flow.

**For these types of tenant deployments, Dex should be configurable so that the user may login using an existing session at Microsoft without seeing this prompt.**

### Proposed Solution

Microsoft offers several "hinting" strings for an application to provide at the Authorization code redirect as query parameters.  The simplest is the `domain_hint` parameter, which allows the application to provide the user email's domain name.

[Microsoft's "Request an authorization code" documentation](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow#request-an-authorization-code) excerpt:

> `domain_hint` | optional | If included, the app skips the email-based discovery process that user goes through on the sign-in page, leading to a slightly more streamlined user experience. For example, sending them to their federated identity provider. Apps can use this parameter during reauthentication, by extracting the tid from a previous sign-in.
> -- | -- | --


**A parameter could be added in the Microsoft Connector configuration as `domainHint`.  Administrators who want to streamline this behavior can set this configuration string to their domain and Dex will be pass the string to Microsoft as `domain_hint`.**

No change to behavior for Dex deployments without this parameter.


### Alternatives Considered

Microsoft offers several options for hinting at the correct account, [documented here](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow#request-an-authorization-code)

If the user account is known to Dex before the redirect, Dex could supply the `login_hint` dynamically based on previous logins.  However, this adds significant implementation complexity and would likely require an opt-in configuration flag to prevent changes to existing behavior for the connector.

I think that the `domain_hint` approach still provides value, even if the `login_hint` approach is also added in the future, because it will work for logins without an existing session.


### Additional Information

I've tested the proposed solution in a fork and I am happy with the results.
I hope to PR the changes into Dex if the solution is acceptable to maintainers!
