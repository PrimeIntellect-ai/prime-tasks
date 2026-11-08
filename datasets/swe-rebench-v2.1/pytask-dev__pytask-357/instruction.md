ENH: Improving file-change detection.
#### Is your feature request related to a problem?

Hitting save on a Python file changes its modification timestamp and triggers a rerun of related tasks even if the content is unchanged.

Is it a feature or a bug?

#### Describe the solution you'd like

Let us improve the modification detection of Python files. **(Only Python!)**

Mypy has a two-level hashing solution: `https://github.com/python/mypy/issues/3403`.

[HIDDEN]

### User behavior-breaking implications

Maybe we need a way to force executing tasks. Deleting the product might be more cumbersome than a `--force` flag.

#### API breaking implications

None

### Additional contract requirements

When a Python task file's timestamp and content both change, the task must be recognized as changed and receive the normal changed-task handling. Content-based unchanged detection applies only to Python task files; other file nodes must retain their existing change-detection behavior.
