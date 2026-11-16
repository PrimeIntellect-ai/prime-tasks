Improve handling of invalid PR titles
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the issue has not already been raised


### Issue

- [x] Improve handling of invalid PR titles, it should throw an error instead of silently approving the PR (as per discussion with @simoneb)
- [x] Parse package name from branch name instead of title to avoid namespace issues
- [x] Fix related tests

### Additional contract requirements

- When PR title parsing fails, report the error with the exact message: `Error while parsing PR title, expected: \`bump <package> from <old-version> to <new-version>\``.
