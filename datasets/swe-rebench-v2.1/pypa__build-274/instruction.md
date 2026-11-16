Cannot create venv _without_ symlinks using Command Line Tools build of Python on macOS
See https://bugs.python.org/issue38705.  This seems to have bitten some users lately:

* https://github.com/pypa/packaging-problems/issues/493
* https://github.com/pypa/packaging-problems/issues/488

Note that the venv CLI defaults to using symlinks on platforms other than Windows so we could do the same in build.  We could otherwise discourage build users from relying on the macOS-provided Python.

### Additional contract requirements

When creating a Python 3 isolated environment through the standard-library `venv` path, request symlinks on non-Windows platforms, including macOS, matching the `venv` command's non-Windows default. The created environment's Python executable must remain usable. Advising users not to rely on macOS-provided Python is not a substitute for this behavior.
