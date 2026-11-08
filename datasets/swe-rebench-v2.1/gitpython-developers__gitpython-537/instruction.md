Use of GIT_REPO env-var for setting Repo path in 2.0.9
[This change](https://github.com/gitpython-developers/GitPython/commit/26bb778b34b93537cfbfd5c556d3810f2cf3f76e) in `2.0.9` is a bit problematic:

- Even if a `path` is explicitly provided to the constructor, the `GIT_DIR` environment variable is used instead

- For things like git hooks, `GIT_DIR` is set to `.git` by default. This will result in [`self.git_dir`](https://github.com/gitpython-developers/GitPython/blob/master/git/repo/base.py#L156) being set to `.git` ([HIDDEN]). Consequently, subsequent commands fails (eg: `repo.git.status()`)

### Additional contract requirements

- When `GIT_DIR` is set to a relative path such as `.git`, subsequent repository commands (for example, `repo.git.status()`) must work.
- When a path is explicitly passed to the `Repo` constructor, that path selects the repository even if `GIT_DIR` is set to a different repository.
- When no path is passed to the `Repo` constructor and `GIT_DIR` is set to the location of a repository, `Repo()` opens that repository, even if the current directory is a different repository.
