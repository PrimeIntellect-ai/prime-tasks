ENH: Better handling of pipx install error when requested python version not available
**How would this feature be useful?**
Following the example from [here](https://pypa.github.io/pipx/examples/]:
```bash
pipx install --python python3.7 pycowsay
```
I get a rather unwieldy exception that would be better wrapped into something more end user friendly:

```txt
1 ❯ pipx install --python python3.7 pycowsay
Traceback (most recent call last):
  File "/opt/homebrew/bin/pipx", line 8, in <module>
    sys.exit(cli())
             ^^^^^
  File "/opt/homebrew/Cellar/pipx/1.2.0/libexec/lib/python3.12/site-packages/pipx/main.py", line 863, in cli
    return run_pipx_command(parsed_pipx_args)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/pipx/1.2.0/libexec/lib/python3.12/site-packages/pipx/main.py", line 214, in run_pipx_command
    return commands.install(
           ^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/pipx/1.2.0/libexec/lib/python3.12/site-packages/pipx/commands/install.py", line 59, in install
    venv.create_venv(venv_args, pip_args)
  File "/opt/homebrew/Cellar/pipx/1.2.0/libexec/lib/python3.12/site-packages/pipx/venv.py", line 162, in create_venv
    venv_process = run_subprocess(cmd + venv_args + [str(self.root)])
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/pipx/1.2.0/libexec/lib/python3.12/site-packages/pipx/util.py", line 176, in run_subprocess
    completed_process = subprocess.run(
                        ^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.12/3.12.0/Frameworks/Python.framework/Versions/3.12/lib/python3.12/subprocess.py", line 548, in run
    with Popen(*popenargs, **kwargs) as process:
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/opt/homebrew/Cellar/python@3.12/3.12.0/Frameworks/Python.framework/Versions/3.12/lib/python3.12/subprocess.py", line 1026, in __init__
    self._execute_child(args, executable, preexec_fn, close_fds,
  File "/opt/homebrew/Cellar/python@3.12/3.12.0/Frameworks/Python.framework/Versions/3.12/lib/python3.12/subprocess.py", line 1950, in _execute_child
    raise child_exception_type(errno_num, err_msg, err_filename)
FileNotFoundError: [Errno 2] No such file or directory: 'python3.7'
```

**Describe the solution you'd like**
It appears that `FileNotFoundError` is what you get when you don't have a particular python version installed but ask for.

`pipx` should validate first whether a python version is installed and raise a more user friendly error rather than exposing internals like this (unless one asks for --verbose output).

**Related**
Potentially related issues/PRs I found when looking for duplicates:
- https://github.com/pypa/pipx/issues/613
- https://github.com/pypa/pipx/pull/625

### Additional contract requirements

- When the executable specified with `--python` is not found, the output must include the exact text `No executable for the provided Python version`.
- When the executable specified with `--python` is not found, write output containing the exact text `No executable for the provided Python version` to stdout.
