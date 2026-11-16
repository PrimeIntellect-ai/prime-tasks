Support deleting head branch of GitHub pull requests
add support for this new feature: https://help.github.com/en/articles/managing-the-automatic-deletion-of-branches

### Additional contract requirements

- Add a public field `DeleteBranchOnMerge *bool` to the `Repository` type in package `github`, serialized in JSON as `delete_branch_on_merge`.
- When creating a repository, the `delete_branch_on_merge` setting must be included in the request.
- `Repository.String()` must include the field when it is populated, following the existing struct-stringification convention.
