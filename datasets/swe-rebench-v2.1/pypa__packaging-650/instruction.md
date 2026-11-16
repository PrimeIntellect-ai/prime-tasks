Marker.evaluate with extra=None  fails in 22.0
Previously in v21.3
```py
>>> from packaging.markers import Marker
>>> marker=Marker('extra == "opt-feature"')
>>> marker.evaluate({"extra": None})
False
```

With v22.0, we get,
```py
>>> from packaging.markers import Marker
>>> marker=Marker('extra == "opt-feature"')
>>> marker.evaluate({"extra": None})
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/rth/.miniforge/envs/pyodide-env/lib/python3.10/site-packages/packaging/markers.py", line 241, in evaluate
    return _evaluate_markers(self._markers, current_environment)
  File "/home/rth/.miniforge/envs/pyodide-env/lib/python3.10/site-packages/packaging/markers.py", line 150, in _evaluate_markers
    lhs_value, rhs_value = _normalize(lhs_value, rhs_value, key=environment_key)
  File "/home/rth/.miniforge/envs/pyodide-env/lib/python3.10/site-packages/packaging/markers.py", line 124, in _normalize
    return tuple(canonicalize_name(v) for v in values)
  File "/home/rth/.miniforge/envs/pyodide-env/lib/python3.10/site-packages/packaging/markers.py", line 124, in <genexpr>
    return tuple(canonicalize_name(v) for v in values)
  File "/home/rth/.miniforge/envs/pyodide-env/lib/python3.10/site-packages/packaging/utils.py", line 34, in canonicalize_name
    value = _canonicalize_regex.sub("-", name).lower()
TypeError: expected string or bytes-like object
```

I'm aware of https://github.com/pypa/packaging/pull/550 but it is a breaking change with a not very helpful error message so I'm not sure if it was intended or not.

For instance,  pkg_resources can fail with the above error [here](https://github.com/pypa/setuptools/blob/main/pkg_resources/__init__.py#L3053) (or at least it does  in micropip). The fix is easy in user code, but it still feels like a regression.


Otherwise thanks a lot for the new release!
