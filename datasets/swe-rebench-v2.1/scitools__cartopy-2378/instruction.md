Error initializing LambertConformal projection on sphere with 0.23
### Description
<!-- Please provide a general introduction to the issue/proposal. -->
Found this while trying to upgrade MetPy's CI to run with Cartopy 0.23.

<!--
If you are reporting a bug, attach the *entire* traceback from Python.

If you are proposing an enhancement/new feature, provide links to related articles, reference examples, etc.

If you are asking a question, please ask on StackOverflow and use the cartopy tag. All cartopy
questions on StackOverflow can be found at https://stackoverflow.com/questions/tagged/cartopy
-->

#### Code to reproduce

```python
import cartopy.crs as ccrs
ccrs.LambertConformal(globe=ccrs.Globe(ellipse='sphere'))
```

#### Traceback

```pytb
---------------------------------------------------------------------------
GEOSException                             Traceback (most recent call last)
Cell In[2], line 1
----> 1 ccrs.LambertConformal(globe=ccrs.Globe(ellipse='sphere'))

File [~/miniconda3/envs/py312/lib/python3.12/site-packages/cartopy/crs.py:1795](http://localhost:51607/lab/tree/~/miniconda3/envs/py312/lib/python3.12/site-packages/cartopy/crs.py#line=1794), in LambertConformal.__init__(self, central_longitude, central_latitude, false_easting, false_northing, standard_parallels, globe, cutoff)
   1790     lons[1:-1] = np.linspace(central_longitude - 180 + 0.001,
   1791                              central_longitude + 180 - 0.001, n)
   1793 points = self.transform_points(PlateCarree(globe=globe), lons, lats)
-> 1795 self._boundary = sgeom.LinearRing(points)
   1796 mins = np.min(points, axis=0)
   1797 maxs = np.max(points, axis=0)

File [~/miniconda3/envs/py312/lib/python3.12/site-packages/shapely/geometry/polygon.py:104](http://localhost:51607/lab/tree/~/miniconda3/envs/py312/lib/python3.12/site-packages/shapely/geometry/polygon.py#line=103), in LinearRing.__new__(self, coordinates)
     99 if len(coordinates) == 0:
    100     # empty geometry
    101     # TODO better constructor + should shapely.linearrings handle this?
    102     return shapely.from_wkt("LINEARRING EMPTY")
--> 104 geom = shapely.linearrings(coordinates)
    105 if not isinstance(geom, LinearRing):
    106     raise ValueError("Invalid values passed to LinearRing constructor")

File [~/miniconda3/envs/py312/lib/python3.12/site-packages/shapely/decorators.py:77](http://localhost:51607/lab/tree/~/miniconda3/envs/py312/lib/python3.12/site-packages/shapely/decorators.py#line=76), in multithreading_enabled.<locals>.wrapped(*args, **kwargs)
     75     for arr in array_args:
     76         arr.flags.writeable = False
---> 77     return func(*args, **kwargs)
     78 finally:
     79     for arr, old_flag in zip(array_args, old_flags):

File [~/miniconda3/envs/py312/lib/python3.12/site-packages/shapely/creation.py:171](http://localhost:51607/lab/tree/~/miniconda3/envs/py312/lib/python3.12/site-packages/shapely/creation.py#line=170), in linearrings(coords, y, z, indices, out, **kwargs)
    169 coords = _xyz_to_coords(coords, y, z)
    170 if indices is None:
--> 171     return lib.linearrings(coords, out=out, **kwargs)
    172 else:
    173     return simple_geometries_1d(coords, indices, GeometryType.LINEARRING, out=out)

GEOSException: IllegalArgumentException: Points of LinearRing do not form a closed linestring
```

<details>
 <summary>Full environment definition</summary>

<!-- fill in the following information as appropriate -->

### Operating system


### Cartopy version
0.23

Shapely 2.0.4
</details>
