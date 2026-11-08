FluxPoints.resample_axis fails in 1.3
**Gammapy version**
1.3, dev



**Bug description**
FluxPoints.resample_axis raises an error




**To Reproduce**
In the `analysis_2.py` tutorial, add at the end
```
from gammapy.estimators.utils import get_rebinned_axis
ax_new = get_rebinned_axis(fluxpoint=flux_points, method="min-ts", ts_threshold=10)
flux_points.resample_axis(ax_new)
```

This fails with an error:

```
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[40], line 1
----> 1 flux_points.resample_axis(ax_new)

File ~/Gammapy-dev/gammapy/gammapy/estimators/points/core.py:869, in FluxPoints.resample_axis(self, axis_new)
    867         edge_max = edge_max + axis_new.reference_time
    868     fp = self.slice_by_coord({axis_new.name: slice(edge_min, edge_max)})
--> 869     fp_new = squash_fluxpoints(fp, axis_new)
    870     fluxpoints.append(fp_new)
    872 return self.__class__.from_stack(fluxpoints, axis=axis_new)

File ~/Gammapy-dev/gammapy/gammapy/estimators/points/core.py:55, in squash_fluxpoints(flux_point, axis)
     52 if axis.name != "energy":
     53     geom = geom.to_cube([flux_point.geom.axes["energy"]])
[HIDDEN]
     56 maps["norm_err"] = Map.from_geom(
     57     geom, data=np.sqrt(minimizer.hess_inv.todense()).reshape(geom.data_shape)
     58 )
     59 maps["n_dof"] = Map.from_geom(geom, data=flux_point.geom.axes[axis.name].nbin)

File ~/Gammapy-dev/gammapy/gammapy/maps/core.py:304, in Map.from_geom(geom, meta, data, unit, dtype)
    301     raise ValueError("Unrecognized geom type.")
    303 cls_out = Map._get_map_cls(map_type)
--> 304 return cls_out(geom, data=data, meta=meta, unit=unit, dtype=dtype)

File ~/Gammapy-dev/gammapy/gammapy/maps/region/ndmap.py:56, in RegionNDMap.__init__(self, geom, data, dtype, meta, unit)
     53     meta = {}
     55 self._geom = geom
---> 56 self.data = data
     57 self.meta = meta
     58 self._unit = u.Unit(unit)

File ~/Gammapy-dev/gammapy/gammapy/maps/region/ndmap.py:84, in RegionNDMap.data(self, value)
     81         value = np.expand_dims(value, (-2, -1))
     83 if self.geom.data_shape != value.shape:
---> 84     raise ValueError(
     85         f"Input shape {input_shape} is not compatible with shape from geometry {self.geom.data_shape}"
     86     )
     88 self._data = value

ValueError: Input shape (1,) is not compatible with shape from geometry (1, 1)
```

### Additional contract requirements

- Resampling FluxPoints onto a rebinned axis should complete without the reported geometry/data shape error and return usable FluxPoints data.
