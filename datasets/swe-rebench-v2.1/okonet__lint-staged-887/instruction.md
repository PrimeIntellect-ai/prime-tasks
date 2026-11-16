Git directory is not correctly resolved if GIT_WORK_TREE is set to relative path
### Description

Resolving the git directory will fail if the environment variable `GIT_WORK_TREE` is set to a relative path and lint-staged is run from a subdirectory of a Git repository.

[HIDDEN]

`GIT_WORK_TREE` can be used to set the worktree directory for a Git repo. `GIT_DIR` specifies only the .git directory. `git rev-parse --show-toplevel` will return the Git worktree directory. If it is set to a relative path, it won't work when git commands are called from a subdirectory, as `.` will then translate to the subdirectory.

[HIDDEN]

**Why set GIT_WORK_TREE to a relative path?**

lint-staged is usually called from hook-scripts and if you call `git --work-tree=/ABSOLUTE/PATH/TO/REPO --git-dir=/ABSOLUTE/PATH/TO/REPO/.git commit` from the worktree root, Git will set `GIT_WORK_TREE` to `.`. `GIT_DIR` will remain an absolute path.

### Steps to reproduce

1. Create a Git repo `test-repo`
2. Make a subdirectory (e.g. `my_app`), where your JS app lives and which contains package.json with lint-staged config
3. Modify a file and stage it
4. Run lint-staged from the subdirectory – **THIS WORKS**
5. Go back to your root Git working directory and set `export GIT_WORK_TREE=.`
6. Run lint-staged from the subdirectory – **this will now fail** to detect the git directory, see error below.

### Debug Logs

The Git repo resides at `/Users/USER/Development/test-repo/`. lint-staged resolves it to the subdirectory `/Users/USER/Development/test-repo/my_app`.

<details>
<summary>expand to view</summary>

```
  lint-staged:resolveGitRepo Resolving git repo from `/Users/USER/Development/test-repo/my_app` +0ms
  lint-staged:resolveGitRepo Unset GIT_DIR (was `undefined`) +0ms
  lint-staged:git Running git command [ 'rev-parse', '--show-toplevel' ] +0ms
  lint-staged:resolveGitRepo Failed to resolve git repo with error: [Error: ENOENT: no such file or directory, lstat '/Users/USER/Development/test-repo/my_app/.git'] {
  errno: -2,
  code: 'ENOENT',
  syscall: 'lstat',
  path: '/Users/USER/Development/test-repo/my_app/.git'
} +11ms
✖ Current directory is not a git directory!

```

</details>

### Environment

- **OS:** macOS 10.15
- **Node.js:** v13.3.0
- **`lint-staged`:** 10.2.9

### Additional contract requirements

- When lint-staged runs from a subdirectory of a Git repository while `GIT_WORK_TREE` is set to a relative path, it must still resolve the repository's actual worktree root correctly.
