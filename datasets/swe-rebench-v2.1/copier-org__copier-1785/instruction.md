Inconsistent validator behavior between `copier {copy,recopy}` and `copier update` for computed values
### Describe the problem

Currently, there is a difference in behavior regarding the `validator` expression for computed values (`when: false` with a default value) between the `copier {copy,recopy}` operation and `copier update`. The validator is ignored for `copy`/`recopy` but enforced upon `update`.

This problem came up when configuring a conditional YAML question via `when: <expression>` with a default value where the default value evaluated to an empty string (i.e., `null`/`None` after YAML-parsing) when `when` evaluated to `false` while the validator did not handle the `null`/`None` value correctly and raised an exception upon `copier update`.

[HIDDEN]

A solution to _not_ validate computed values even on `copier update` seems to be as follows – I've tested it locally with an additional test and the test suite is passing as well:

```diff
[HIDDEN]
[HIDDEN]
```

But it isn't obvious to me what the _right_ behavior is. Should computed values be validated or not when a validator is present? In any case, the behavior should be consistent.

### Template

[copier-computed-value-validator.zip](https://github.com/user-attachments/files/17059445/copier-computed-value-validator.zip)


### To Reproduce

```console
# Unzip the reproducible example above
unzip copier-computed-value-validator.zip
# Change directory into the extracted root directory `copier-computed-value-validator`
cd copier-computed-value-validator/
# Run `copier copy src/ dst/` with the above template and observe no error
copier copy src/ dst/
# Change directory to the destination directory
cd dst/
# Git-initialize the project and make an initial commit
git init
git add .
git commit -m "initial commit"
# Change directory one level up again
cd ..
# Run `copier update dst/` and observe the error
copier update dst/
```

### Logs

```console
$ copier update dst/
No git tags found in template; using HEAD as ref
Updating to template version 0.0.0.post1.dev0+751d554
No git tags found in template; using HEAD as ref
No git tags found in template; using HEAD as ref
Traceback (most recent call last):
  File "$HOME/.local/bin/copier", line 8, in <module>
    sys.exit(copier_app_run())
             ^^^^^^^^^^^^^^^^
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/plumbum/cli/application.py", line 638, in run
    inst, retcode = subapp.run(argv, exit=False)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/plumbum/cli/application.py", line 633, in run
    retcode = inst.main(*tailargs)
              ^^^^^^^^^^^^^^^^^^^^
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 425, in main
    return _handle_exceptions(inner)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 70, in _handle_exceptions
    method()
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 415, in inner
    with self._worker(
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 228, in __exit__
    raise value
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 423, in inner
    worker.run_update()
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 899, in run_update
    self._apply_update()
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 966, in _apply_update
    with replace(
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 228, in __exit__
    raise value
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 974, in _apply_update
    new_worker.run_copy()
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 817, in run_copy
    self._ask()
  File "$HOME/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 491, in _ask
    raise ValueError(f"Validation error for question '{var_name}': {err_msg}")
ValueError: Validation error for question 'computed_value': Should this validator be rendered or not?
```


### Expected behavior

Either the validation is skipped on `copier update` or the validation error should also occur on `copier {copy,recopy}`. I'm not sure what's best. Opinions are most welcome.

### Screenshots/screencasts/logs

_No response_

### Operating system

Linux

### Operating system distribution and version

Ubuntu 22.04

### Copier version

copier 9.3.1

### Python version

CPython 3.12

### Installation method

pipx+pypi

### Additional context

_No response_

### Additional contract requirements

- For questions with `when: false` and a default value, validator behavior must be consistent across `copier copy`, `copier recopy`, and `copier update`: validation must either be skipped in all three operations or enforced in all three.
