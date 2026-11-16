Add a single character shortcut for --no-reuse-existing-virtualenvs
### How would this feature be useful?

A common way to use Nox that saves a lot of time when re-running sessions over and over by avoiding recreating venvs is to set:

```py
nox.options.reuse_existing_virtualenvs = True
```

You can see the `pip` developers use this:

- https://github.com/pypa/pip/blob/main/noxfile.py#L19

When dependencies _do_ change, the developer can then run:

```
nox --no-reuse-existing-virtualenvs -s test
```

Given this can be a very common work flow, avoiding having to type out `--no-reuse-existing-virtualenvs` on the command line would be a great improvement to UX.

### A note on `tox`

What I'm describing above is also the default workflow for `tox` users. Many people moving from `tox` will be familiar with this workflow. (e.g. `tox` re-uses venvs by default, and `tox -r` is an opt-in recreation).

### Describe the solution you'd like

Add a new alias for `--no-reuse-existing-virtualenvs`, for example `-C` for "Create"

```
nox -C -s test
```

### Additional contract requirements

- The command line must accept `-N` as the single-character alias of `--no-reuse-existing-virtualenvs`. Passing `-N` disables reuse of existing virtualenvs for that invocation, with the same effect as the long option, including when `--reuse-existing-virtualenvs` is also given.
