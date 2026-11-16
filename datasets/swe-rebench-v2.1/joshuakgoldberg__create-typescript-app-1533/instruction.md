🚀 Feature: Use get-github-auth-token instead of $(gh auth token)
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

I just published https://github.com/JoshuaKGoldberg/get-github-auth-token, which is a small utility that attempts to find a GitHub auth token from the following places, in order:

1. `process.env.GH_TOKEN`
2. Executing `gh auth token` as a child process

Let's use that as the underlying way to get GitHub auth tokens. This can work as a precursor to #667 -> #1000.

### Additional Info

💖

### Additional contract requirements

- Use the package’s `getGitHubAuthToken()` export to obtain the token. It returns a promise resolving to an object with `succeeded: true` and a `token` string on success, or `succeeded: false` and an `error` string on failure. Use the token on success and treat a failure result as failed GitHub authentication.
