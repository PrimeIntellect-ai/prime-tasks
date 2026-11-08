Feature: specific references in forbidden-uses
### Pre-submission checks

- [x] I am **not** reporting a bug (crash, false positive/negative, etc). These must be filed via the bug report template.
- [x] I have looked through the open issues for a duplicate request.

### What's the problem this feature will solve?

Developers might update an action or add a new action without vetting that it's trustworthy.

### Describe the solution you'd like

Having an allow-list that includes the concrete SHA would help here.

### Additional context

_No response_

### Additional contract requirements

- The `forbidden-uses` audit's `allow` and `deny` configuration lists accept
  repository `uses:` patterns that include an explicit Git ref, written as
  `owner/repo@ref`. Such a pattern matches exactly the `uses:` clause with that
  owner, repo and ref.
- A repository `uses:` pattern that combines a wildcard with an explicit ref
  (for example `owner/repo/*@ref`) is invalid and must be rejected.
- The `unpinned-uses` audit's configuration rejects patterns that include an
  explicit Git ref, reporting the error message
  `can't use exact ref patterns here`.
