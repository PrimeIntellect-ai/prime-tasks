Add `__eq__` to `Requirement` and `Marker`
It would be useful to declare `__eq__` in `packaging.requirements.Requirement` and `packaging.markers.Marker` so that we can compare them.

Currently:
```python
>>> from packaging.requirements import Requirement
>>> Requirement('package') == Requirement('package')
False
>>> from packaging.markers import Marker
>>> Marker('os_name == "nt"') == Marker('os_name == "nt"')
False
```
