Support GCPs without known z coordinate
Ground Control Points are allowed to omit elevation component, however logic in here assumes GCPs are always in `x,y,z` form:

https://github.com/corteva/rioxarray/blob/166c0c76d9e174387ca6b2368f7eb6a3d07ec13a/rioxarray/rioxarray.py#L1255

When geometry is specified with only `x,y` coordinates `IndexError` is raised when calling `.rio.get_gcps()`.

Code here

https://github.com/corteva/rioxarray/blob/166c0c76d9e174387ca6b2368f7eb6a3d07ec13a/rioxarray/rioxarray.py#L1289

should probably generate `[float, float]` instead of `[float, float, None]` when GCP is missing height information.
