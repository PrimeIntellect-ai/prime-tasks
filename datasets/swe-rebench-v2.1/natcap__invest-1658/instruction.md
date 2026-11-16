CV: TypeError: 'MultiLineString' object is not iterable
This is a somewhat rare edge case that comes up with complicated landmasses & AOIs. It's hard enough to contrive an example that we don't test for it, apparently. Our code to handle `MultLineString` iteration simply is not compatible with Shapely 2.0. https://shapely.readthedocs.io/en/stable/migration.html#multi-part-geometries-will-no-longer-be-sequences-length-iterable-indexable

I have some user's data so I can reproduce and fix it.

```python
Traceback (most recent call last):
  File "taskgraph\Task.py", line 674, in add_task
  File "taskgraph\Task.py", line 1093, in _call
  File "natcap\invest\coastal_vulnerability.py", line 1176, in prepare_landmass_line_index_and_interpolate_shore_points
TypeError: 'MultiLineString' object is not iterable
10/21/2024 17:29:44  natcap.invest.utils ERROR    Exception while executing natcap.invest.coastal_vulnerability
Traceback (most recent call last):
  File "natcap\invest\utils.py", line 165, in prepare_workspace
  File "invest\cli.py", line 470, in main
  File "natcap\invest\coastal_vulnerability.py", line 856, in execute
  File "taskgraph\Task.py", line 674, in add_task
  File "taskgraph\Task.py", line 1093, in _call
  File "natcap\invest\coastal_vulnerability.py", line 1176, in prepare_landmass_line_index_and_interpolate_shore_points
TypeError: 'MultiLineString' object is not iterable
```
