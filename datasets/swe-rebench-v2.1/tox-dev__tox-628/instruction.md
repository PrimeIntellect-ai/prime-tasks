tox --version should display loaded plugins
It seems that currently tox is very secretive about which plugins it did load and that's not giving the best user experience.

Based on the implementations from other tools, usually they display plugin information alongside with their versions, because that results describes the best what you really run.

One nice example is ``pytest --version``:
```
pytest --version                                                                                                                                                              [15:24:20]
This is pytest version 3.0.7, imported from /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/pytest.pyc
setuptools registered plugins:
  pytest-xdist-1.15.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/xdist/boxed.py
  pytest-xdist-1.15.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/xdist/looponfail.py
  pytest-xdist-1.15.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/xdist/plugin.py
  pytest-pep8-1.0.6 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/pytest_pep8.py
  pytest-mock-1.6.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/pytest_mock.py
  pytest-instafail-0.3.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/pytest_instafail.py
  pytest-cov-2.4.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/pytest_cov/plugin.py
  flaky-3.3.0 at /Users/ssbarnea/.venv/rh/lib/python2.7/site-packages/flaky/flaky_pytest_plugin.py
```
