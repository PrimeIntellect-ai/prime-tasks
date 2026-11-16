Retreive response headers
<!--
**Please do not report security vulnerabilities here**. The Responsible Disclosure Program (https://auth0.com/whitehat) details the procedure for disclosing security issues.

Thank you in advance for helping us to improve this library! Your attention to detail here is greatly appreciated and will help us respond as quickly as possible. For general support or usage questions, use the Auth0 Community (https://community.auth0.com/) or Auth0 Support (https://support.auth0.com/). Finally, to avoid duplicates, please search existing Issues before submitting one here.

By submitting an Issue to this repository, you agree to the terms within the Auth0 Code of Conduct (https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).
-->

### Describe the problem you'd like to have solved

Using the management API to retrieve users which works fine. Now I need to have access to the response headers to tackle a rate limiting issue. Like described [here](https://auth0.com/docs/troubleshoot/customer-support/operational-policies/rate-limit-policy#handle-rates-limitations-in-code). I need to have access to the auth0 response headers x-ratelimit-limit,  x-ratelimit-remaining and x-ratelimit-reset. I was not able to get the response headers from auth0.

While checking the management api code I found out that the headers from the rest-fasade (used client) are not being passed back to the results.


<!--
> A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]
-->

### The ideal solution

I would like to be able to get the headers together with the response body.
```
const auth0ApiClient = new ManagementClient(...)
auth0ApiClient.getUser({ id: customerId }.then((body, headers) => {
    console.log("Headers: ", headers)
})
```

Let me know If there is a workaround within the management API to solve this issue.

### Additional contract requirements

When a `ManagementClient` is constructed with `includeResponseHeaders: true`, successful management API calls must return the response body and HTTP response headers together as `{ data, headers }`. This applies to manager methods and the corresponding shorthand methods. The `headers` value must make the `x-ratelimit-limit`, `x-ratelimit-remaining`, and `x-ratelimit-reset` response headers available to callers.
