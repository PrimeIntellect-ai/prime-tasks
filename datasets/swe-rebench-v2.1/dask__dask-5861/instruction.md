pip command line warning
Recently versions of `pip` (20.0+) emit the following warning when using the `pip` CLI (e.g. `pip install <package-name>`):

```
WARNING: pip is being invoked by an old script wrapper. This will fail in a future version of pip.
Please see https://github.com/pypa/pip/issues/5599 for advice on fixing the underlying issue.
To avoid this problem you can invoke Python with '-m pip' instead of running pip directly.
```

We should go through and replace occurrences of using `pip` directly in the codebase with `python -m pip`. So things like `pip install <package-name>` should be replaced with `python -m pip install <package-name>`
