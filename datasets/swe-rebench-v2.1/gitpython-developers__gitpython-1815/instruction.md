Git.refresh warns to stdout and does not log
Warning messages are most often written to standard error. Furthermore, warnings from GitPython, when they are displayed, are in most cases displayed that way unless the caller arranges otherwise, because they are displayed by calling loggers' `warning` methods or, for `DeprecationWarning`s, by calling `warnings.warn`.

However, the warning `Git.refresh` displays when running a test command like `git --version` (with the command being tested used for `git`) fails, and `GIT_PYTHON_REFRESH` is set to `1`, `w`, `warn`, or `warning`, is different. It is printed to standard output. It also does not use any logging facility, so attempts to capture it by configuring Python logging will not succeed.

https://github.com/gitpython-developers/GitPython/blob/d28c20b1dbf18dc60a2b1859e818801bd8d742f2/git/cmd.py#L453-L454

If there is a reason for this behavior, then I think it should be commented or otherwise stated. Otherwise, I am not sure what to do. It may still not be feasible to change, because programs that use GitPython may be relying on the warning being printed to standard output, or on it not being printed to standard error. But if he behavior is going to change in the next major version, then that could be commented and/or this issue could be kept open until then. If the reason is unknown and it is undecided whether the behavior should be changed in the next major release, then a comment could be added just saying that it prints to standard output for backward compatibility.

### Additional contract requirements

- The `git` package exposes a public function `refresh(executable_path=None)` that re-initialises the git executable lookup.
- `Git.GIT_PYTHON_GIT_EXECUTABLE` is a public class attribute holding the current git executable path or name.
- When the initial refresh fails to find a working git executable and the refresh mode is a warning mode, the warning is emitted through the logger for the `git.cmd` module, so that it can be captured by configuring Python logging, rather than being printed to standard output.
