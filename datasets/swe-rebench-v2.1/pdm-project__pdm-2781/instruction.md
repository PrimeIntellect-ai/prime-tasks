PDM doesn't find Python interpreters when PDM_IGNORE_ACTIVE_VENV is set
- [x] I have searched the issue tracker and believe that this is not a duplicate.

**Make sure you run commands with `-v` flag before pasting the output.**

## Steps to reproduce

<!--Describe the minimized example of how to reproduce the bug-->

1.  Have some Python version `>=3.10` installed
2. Use following minimal `pyproject.toml`

   ```toml
   [project]
   name = "test"
   version = "0.0.1"
   requires-python = ">=3.10"
   ```

3. Set environment variable `PDM_IGNORE_SAVED_PYTHON` and `PDM_IGNORE_ACTIVE_VENV`.
4. Try to install the project:

   ```shell
   pdm install --verbose
   ```

## Actual behavior

<!--A clear and concise description the result of the above steps-->

PDM does not find a Python version to use and errors out:

```
PS C:\Users\progalski\git\test> pdm install --verbose
WARNING: Lockfile does not exist
Updating the lock file...
[NoPythonVersion]: No Python that satisfies >=3.10 is found on the system.
```

## Expected behavior

<!--A clear and concise description of what you expected to happen.-->

According to [PDM Docs: Virtualenv auto-detection](https://pdm-project.org/latest/usage/venv/#virtualenv-auto-detection) I would expect that PDM creates a new virtual environment because virtual env auto-detection fails.

## Environment Information

```bash
# Paste the output of `pdm info && pdm info --env` below:
PS C:\Users\progalski\git\test> pdm info && pdm info --env
[NoPythonVersion]: No Python that satisfies >=3.10 is found on the system.
```

Environment Information without the problematic environment variables set:
```bash
# Paste the output of `pdm info && pdm info --env` below:
PDM version:
  2.13.2
Python Interpreter:
  C:\Users\progalski\git\test\.venv\Scripts\python.exe (3.11)
Project Root:
  C:/Users/progalski/git/test
Local Packages:

{
  "implementation_name": "cpython",
  "implementation_version": "3.11.4",
  "os_name": "nt",
  "platform_machine": "AMD64",
  "platform_release": "10",
  "platform_system": "Windows",
  "platform_version": "10.0.22631",
  "python_full_version": "3.11.4",
  "platform_python_implementation": "CPython",
  "python_version": "3.11",
  "sys_platform": "win32"
}
```

### Additional contract requirements

Add a public function `is_path_relative_to(path, base) -> bool` in module `pdm.utils`. It returns `True` when `path` is located inside `base` (including when both refer to the same location), otherwise `False`. Both `path` and `base` accept either `pathlib.Path` objects or strings.

When `PDM_IGNORE_ACTIVE_VENV` is set, PDM must still find a compatible interpreter outside the active virtual environment. If virtual-environment use is enabled and active-environment auto-detection is ignored, installation must create and use a project virtual environment rather than reuse the active environment.
