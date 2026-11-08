Drop support for Python 3.5
[Python 3.5 reached EOL on 2020-09-13](https://devguide.python.org/#status-of-python-branches). I think it would be reasonable to **keep pyinaturalist compatible with Python 3.5 through v0.11**. For v0.12+, we can remove 3.5 from the tox tests and start making use of Python 3.6 features: f-strings, type annotations for variables, etc.

Also see #32.

### Additional contract requirements

For v0.12+, Python 3.5 must be removed from the project's test and support configuration:
- `tox.ini` must not list a `py35` environment (neither in `envlist` nor as a `[testenv:py35]` section).
- `setup.cfg` must not declare the `Programming Language :: Python :: 3.5` classifier.
- `.travis.yml` must not include a Python 3.5 job.
