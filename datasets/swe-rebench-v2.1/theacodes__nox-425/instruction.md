Regression: Nox crashes with AttributeError: module 'sys' has no attribute 'real_prefix' when reusing virtualenvs
<!-- Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can. -->

**Describe the bug**
On the main branch, `nox -r` crashes with `AttributeError: module 'sys' has no attribute 'real_prefix'`. This appears to be a regression from #418.

**How to reproduce**
Install Nox into a virtualenv, and run its own test suite using -r.

```
$ git clone https://github.com/theacodes/nox
$ cd nox
$ virtualenv venv
$ . venv/bin/activate
$ pip install -e .
$ nox -rs tests -p 3.9
nox > Running session tests-3.9
nox > python3.9 -c import sys; print(sys.prefix)
nox > .../nox/.nox/tests-3-9/bin/python -c import sys; print(sys.real_prefix)
nox > Command .../nox/.nox/tests-3-9/bin/python -c import sys; print(sys.real_prefix) failed with exit code 1:
Traceback (most recent call last):
  File "<string>", line 1, in <module>
AttributeError: module 'sys' has no attribute 'real_prefix'
nox > Session tests-3.9 failed.
```

**Expected behavior**
Nox reuses the virtual environment without crashing.

### Additional contract requirements

When reusing an existing virtual environment, Nox must only keep it if its environment type and selected Python interpreter are compatible with the requested environment; otherwise, Nox must replace it.
