Non-tagged Python builds use non-PEP 440 versions
Sorry if this should be a new issue. I have a problem where the version of Python itself is causing an Invalid Version error.  I install Python from the tip of 3.12, then:

```
% .tox/anypy/bin/python -c "import pkg_resources as p; p.load_entry_point('coverage', 'console_scripts', 'coverage')()"
Traceback (most recent call last):
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2711, in _dep_map
    return self.__dep_map
           ^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2826, in __getattr__
    raise AttributeError(attr)
AttributeError: _Distribution__dep_map

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 522, in load_entry_point
    return get_distribution(dist).load_entry_point(group, name)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2855, in load_entry_point
    return ep.load()
           ^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2467, in load
    self.require(*args, **kwargs)
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2489, in require
    reqs = self.dist.requires(self.extras)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2746, in requires
    dm = self._dep_map
         ^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2713, in _dep_map
    self.__dep_map = self._filter_extras(self._build_dep_map())
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 2728, in _filter_extras
    invalid_marker(marker) or not evaluate_marker(marker)
    ^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 1415, in invalid_marker
    evaluate_marker(text)
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/__init__.py", line 1433, in evaluate_marker
    return marker.evaluate()
           ^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/_vendor/packaging/markers.py", line 245, in evaluate
    return _evaluate_markers(self._markers, current_environment)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/_vendor/packaging/markers.py", line 151, in _evaluate_markers
    groups[-1].append(_eval_op(lhs_value, op, rhs_value))
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/_vendor/packaging/markers.py", line 109, in _eval_op
    return spec.contains(lhs, prereleases=True)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/_vendor/packaging/specifiers.py", line 565, in contains
    normalized_item = _coerce_version(item)
                      ^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/_vendor/packaging/specifiers.py", line 36, in _coerce_version
    version = Version(version)
              ^^^^^^^^^^^^^^^^
  File "/Users/nedbatchelder/coverage/trunk/.tox/anypy/lib/python3.12/site-packages/pkg_resources/_vendor/packaging/version.py", line 197, in __init__
    raise InvalidVersion(f"Invalid version: '{version}'")
pkg_resources.extern.packaging.version.InvalidVersion: Invalid version: '3.12.0a5+'

% .tox/anypy/bin/python -m pip freeze --all
attrs==22.2.0
colorama==0.4.6
-e git+ssh://git@github.com/nedbat/coveragepy.git@1edd0608fac9ffadf24da72820572bec43d0c8fd#egg=coverage
distlib==0.3.6
exceptiongroup==1.1.0
execnet==1.9.0
filelock==3.9.0
flaky==3.7.0
hypothesis==6.68.0
importlib-metadata==6.0.0
iniconfig==2.0.0
packaging==23.0
pip==23.0
platformdirs==3.0.0
pluggy==1.0.0
pytest==7.2.1
pytest-xdist==3.2.0
setuptools==67.2.0
sortedcontainers==2.4.0
tomli==2.0.1
typing_extensions==4.4.0
virtualenv==20.19.0
wheel==0.38.4
zipp==3.12.1
```

Why is setuptools trying to parse the Python version?

There's a corresponding [coverage.py issue about this](https://github.com/nedbat/coveragepy/issues/1556).

_Originally posted by @nedbat in https://github.com/pypa/setuptools/issues/3772#issuecomment-1427828485_

### Additional contract requirements

- When `Marker("python_full_version < '3.12'").evaluate` is called with `{"python_full_version": "3.11.1+"}`, it must raise `packaging.version.InvalidVersion`.
