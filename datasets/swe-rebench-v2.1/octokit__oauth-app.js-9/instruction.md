Handle callback errors
**What’s missing?**

If an authorization error occurs, the callback redirect has different query parameters. Example

```
?error=redirect_uri_mismatch&error_description=The+redirect_uri+MUST+match+the+registered+callback+URL+for+this+application.&error_uri=https%3A%2F%2Fdeveloper.github.com%2Fapps%2Fmanaging-oauth-apps%2Ftroubleshooting-authorization-request-errors%2F%23redirect-uri-mismatch
```

**Why?**

It's a standard error behavior of GitHub's API and should be covered by Octokit

### Additional contract requirements

- For a GET request to `/api/github/oauth/callback`, if the query contains an authorization `error` and `error_description`, treat the callback as an error rather than exchanging a code. Respond with HTTP 400 and a JSON body whose `error` value is `[@octokit/oauth-app] ` followed by the error code, a space, and the description. For example, `error=redirect_uri_mismatch` with the description `The redirect_uri MUST match the registered callback URL for this application.` produces `{"error":"[@octokit/oauth-app] redirect_uri_mismatch The redirect_uri MUST match the registered callback URL for this application."}`.
