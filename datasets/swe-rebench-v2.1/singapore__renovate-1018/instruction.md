Better rebasing
Create repo with one devDependency range.
Merge Configure Removate PR
Wait for Pin Dependencies PR
Update master branch with a second devDependency range
Run Renovate again

Renovate will warn that it can't replace the value.

Expected: Renovate should rebase from master, because pr.canRebase = true
We should only commit on top of an existing branch if it can't be rebased (i.e. user had edited it)

### Additional contract requirements

- `getParentBranch(config)` (module `lib/workers/branch/parent`) returns an object with:
  - `parentBranch`: the branch to use as the parent for the new PR, or `undefined` when the default branch should be used.
  - `canRebase`: `false` when an existing branch cannot be rebased.
- `getUpdatedPackageFiles(config)` (module `lib/workers/branch/package-files`) returns an object with:
  - `updatedPackageFiles`: an array of objects, each with `name` (the package file path) and `contents` (the new file contents).
  - `parentBranch`: the incoming `parentBranch` value, or `undefined` when a rebase is required.
  - When a package file cannot be updated and rebasing is possible, the update is retried from the default branch; otherwise an error is thrown.
- `setNewValue(currentFileContent, depType, depName, newVersion, logger)` (module `lib/workers/branch/package-json`) returns the updated file content as a string, or `null` when processing throws.
