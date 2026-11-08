Respect the active virtual environment instead of the installed location
### Describe the feature

If `pipdeptree` is installed in the system python location (to make it always accessible), it will by default use the system python to look for packages. When a virtual environment is activated, this causes a confusing situation where packages listed do not correspond to the activated environment.

To work around this, a user has to manually provide the desired python:
```shell
# activate env
conda activate <env>  # or other virtualenv equivalent
# look for package
pipdeptree -p <package> --local-only --python "$(which python)"
```

Installing `pipdeptree` as a system-wide utility seems relevant to avoid reinstalling it each time for each environment (similar to what `poetry` recommends).

It seems to me that `pipdeptree` should prioritize the "active" python rather than its installed location.

### Additional contract requirements

When `pipdeptree` is invoked with `--python auto` while a virtual environment is active, it must use that environment's interpreter to discover packages rather than the interpreter where `pipdeptree` is installed.
