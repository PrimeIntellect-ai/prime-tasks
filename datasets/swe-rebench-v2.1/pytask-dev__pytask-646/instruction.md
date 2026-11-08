ENH: Add a `.gitignore` to `.pytask` to prevent it from being added to git.
Same as in pytest, virtualenv and also the builtin venv module.

### Additional contract requirements

- `pytask.build` accepts an optional `paths` argument that is a path or a collection of paths and returns a session object with an `exit_code` attribute of type `pytask.ExitCode`.
