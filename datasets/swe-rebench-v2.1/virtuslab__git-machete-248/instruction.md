Check first if given pull request is closed in `github checkout-pr`
Github Api returns all opened pull requests after `GET` on [pulls endpoint](https://docs.github.com/en/rest/reference/pulls).

During `github checkout-pr` on pull request which is already closed, git-machete ends up with message:
```
$ git machete github checkout-pr 204

PR number 204 is not found in repository git-machete
```
Scope of this issue is to make distinction in the error message when pull request is closed or never created.

### Additional contract requirements

- When `github checkout-prs 23` checks out the closed PR, it must emit `Warn: Pull request #23 is already closed.`
- When PR #5 has head branch `bugfix/remove-n-option` deleted from `origin`, checkout must fail with exactly: `Could not check out PR #5 because its head branch `bugfix/remove-n-option` is already deleted from `origin`.`
