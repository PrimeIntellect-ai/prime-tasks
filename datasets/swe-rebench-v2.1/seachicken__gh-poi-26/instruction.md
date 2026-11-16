Delete checked out PR branches
**Description**
When a PR branch is currently checked out, `gh-poi` will not delete the branch. A way to fix this would be to checkout the default branch and _then_ delete the branch.

**Additional context**

[hub-sync](https://hub.github.com/hub-sync.1.html) implemented this same functionality and the way I described above is how this tool dealt with the problem.

### Additional contract requirements

- `GetBranches(conn Connection, check bool) ([]Branch, error)` in `poi.go` returns the local branches and their state. When a deletable branch is currently checked out, it reports the default branch as the checked-out branch, adding it when it is not present. When `check` is `false`, it checks out the default branch before returning; when `check` is `true`, it does not perform that checkout. It returns an error when an external command fails.
- The `Connection` interface in `poi.go` declares `GetAssociatedRefNames(oid string) (string, error)`, `GetUncommittedChanges() (string, error)` and `CheckoutBranch(branchName string) (string, error)`, and `ConnectionImpl` implements them.
- `GetUncommittedChanges` reports the pending changes in the working tree: it returns an empty string when the working tree is clean and a non-empty string when there are pending changes. A checked-out branch with pending changes is reported as not deletable.
- `GetAssociatedRefNames` returns the names of all refs, including local and remote refs, that contain the given commit.
- `CheckoutBranch` switches the current branch to the given branch name.
