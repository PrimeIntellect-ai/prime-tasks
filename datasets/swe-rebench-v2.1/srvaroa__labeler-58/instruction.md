add condition for draft pull requests
as far as I understand, you can only determine between mergeable true/false, but it would be also nice to check whether it is a draft PR or not.

### Additional contract requirements

A label matcher may use the pull request's draft status as a condition. The matcher configuration key is `draft`: `true` matches draft pull requests, `false` matches pull requests that are not drafts.
