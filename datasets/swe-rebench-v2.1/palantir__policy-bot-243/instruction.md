support predicate for source branch
It seems like it would be useful to have an analogous version of `targets_branch` for specifying the source branch. For my particular use case, I would like to have a policy where pull requests to the `master` branch can only come from the `develop` branch.

### Additional contract requirements

- The source-branch predicate is configured in a rule's `if` block under the key `from_branch`, with a `pattern` field holding a regular expression that is matched against the pull request's source (head) branch name.
- A rule whose `from_branch` pattern matches the source branch is satisfied; a rule whose pattern does not match is not satisfied (the rule is skipped).
- When the `from_branch` pattern matches the source branch, the predicate's description is empty; when it does not match, the description is a non-empty message explaining that the source branch does not match the configured pattern.
- For a pull request whose head is in a different repository, the source branch name is the head repository owner followed by the branch name in `owner:branch` form (for example `testorg2:test-branch`), and the `from_branch` pattern is matched against this full value.
