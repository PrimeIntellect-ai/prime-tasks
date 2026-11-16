`checkout_github_prs()` should NOT fail if no PRs for the given criteria are found

### Additional contract requirements

- For `github checkout-prs --by tester`, when no open pull requests match, the command must succeed and print exactly `Warn: User `tester` has no open pull request in repository `{org}/{repo}`\n`, using the repository's actual organization and name.
