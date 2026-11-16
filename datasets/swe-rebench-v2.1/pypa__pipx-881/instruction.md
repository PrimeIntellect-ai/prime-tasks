Install a .whl file containing console entry point
**How would this feature be useful?**

If a user creates a `.whl` file that contains an [`entry_point` `console_script`](https://python-packaging.readthedocs.io/en/latest/command-line-scripts.html#the-console-scripts-entry-point), normally they can run:

```bash
(venv) $ pip install myproject-0.1.0-py3-none-any.whl
```

And then those entry points are available within the virtual environment.

But when I try to do something similar with `pipx`:

```
$ pipx install myproject-0.1.0-py3-none-any.whl
Fatal error from pip prevented installation. Full pip output in file:
    ~/.local/pipx/logs/cmd_2021-03-02_14.39.35_pip_errors.log

Some possibly relevant errors from pip install:
    ERROR: Could not find a version that satisfies the requirement myproject-0-1-0-py3-none-any-whl
    ERROR: No matching distribution found for myproject-0-1-0-py3-none-any-whl

Error installing myproject-0-1-0-py3-none-any-whl.
```

It seems like the `.whl` file name is being normalized into a PyPI name?

**Describe the solution you'd like**

Be able to run

```
$ pipx install myproject-0.1.0-py3-none-any.whl
```

And it installs the package into the `pipx` environment, making the console entry points available in the PATH.

### Additional contract requirements

- `pipx install <path>` where `<path>` is a local `.whl` file must install that wheel instead of treating the file name as a PyPI package name.
- After a successful install, pipx reports the installed console entry points, listing each one on its own line prefixed with `- ` (for example `- repeatme`), and makes each entry point available on `PATH`.
