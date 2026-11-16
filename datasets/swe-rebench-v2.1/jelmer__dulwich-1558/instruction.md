Porcelain function for switching branch that updates working tree
update_head() lets you change the branch, but the working tree does not get updated. I don't see anyway to accomplish this with just porcelain. There should be some way to get the same behavior as

`git checkout 'branch_name'`

### Additional contract requirements

- Provide a porcelain function named `checkout(repo, target)` in `dulwich.porcelain`, where `repo` is a repository object and `target` is a branch name given as bytes (for example `b"feature"`).
- Calling it switches the repository to that branch, so that `active_branch` reports the branch name afterwards.
- The working tree is updated to match the branch: files that exist only on the target branch are created, files whose content differs are rewritten with the target content, and files that exist only on the previous branch are removed.
- After a switch made from a clean working tree, `status` reports no staged or unstaged changes.
