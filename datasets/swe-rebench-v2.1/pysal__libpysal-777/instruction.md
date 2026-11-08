GEOS induced topological error in voronoi_frames
```py
import geopandas as gpd
from libpysal.cg import voronoi_frames

blg = gpd.read_parquet('faulty_blg.pq')
encl = gpd.read_parquet('faulty_encl.pq')
voronoi_frames(blg, clip=encl.geometry.item(), shrink=0.4, segment=0.5)

---------------------------------------------------------------------------
GEOSException                             Traceback (most recent call last)
Cell In[22], line 7
      5 blg = gpd.read_parquet('/Users/martin/Downloads/faulty_blg.pq')
      6 encl = gpd.read_parquet('/Users/martin/Downloads/faulty_encl.pq')
----> 7 voronoi_frames(blg, clip=encl.geometry.item(), shrink=0.4, segment=0.5)

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/libpysal/cg/voronoi.py:458, in voronoi_frames(geometry, radius, clip, shrink, segment, grid_size, return_input, as_gdf)
    450     ids_objects, ids_polygons = polygons.sindex.query_bulk(
    451         objects, predicate="intersects"
    452     )
    453 if mask_poly.any() or mask_line.any():
    454     # Dissolve polygons
    455     polygons = (
    456         polygons.iloc[ids_polygons]
    457         .groupby(objects.index.take(ids_objects))
--> 458         .agg(shapely.coverage_union_all)
    459     )
    460     if geometry.crs is not None:
    461         polygons = polygons.set_crs(geometry.crs)

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/pandas/core/groupby/generic.py:294, in SeriesGroupBy.aggregate(self, func, engine, engine_kwargs, *args, **kwargs)
    291     return self._python_agg_general(func, *args, **kwargs)
    293 try:
--> 294     return self._python_agg_general(func, *args, **kwargs)
    295 except KeyError:
    296     # KeyError raised in test_groupby.test_basic is bc the func does
    297     #  a dictionary lookup on group.name, but group name is not
    298     #  pinned in _python_agg_general, only in _aggregate_named
    299     result = self._aggregate_named(func, *args, **kwargs)

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/pandas/core/groupby/generic.py:327, in SeriesGroupBy._python_agg_general(self, func, *args, **kwargs)
    324 f = lambda x: func(x, *args, **kwargs)
    326 obj = self._obj_with_exclusions
--> 327 result = self._grouper.agg_series(obj, f)
    328 res = obj._constructor(result, name=obj.name)
    329 return self._wrap_aggregated_output(res)

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/pandas/core/groupby/ops.py:864, in BaseGrouper.agg_series(self, obj, func, preserve_dtype)
    857 if not isinstance(obj._values, np.ndarray):
    858     # we can preserve a little bit more aggressively with EA dtype
    859     #  because maybe_cast_pointwise_result will do a try/except
    860     #  with _from_sequence.  NB we are assuming here that _from_sequence
    861     #  is sufficiently strict that it casts appropriately.
    862     preserve_dtype = True
--> 864 result = self._aggregate_series_pure_python(obj, func)
    866 npvalues = lib.maybe_convert_objects(result, try_float=False)
    867 if preserve_dtype:

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/pandas/core/groupby/ops.py:885, in BaseGrouper._aggregate_series_pure_python(self, obj, func)
    882 splitter = self._get_splitter(obj, axis=0)
    884 for i, group in enumerate(splitter):
--> 885     res = func(group)
    886     res = extract_result(res)
    888     if not initialized:
    889         # We only do this validation on the first iteration

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/pandas/core/groupby/generic.py:324, in SeriesGroupBy._python_agg_general.<locals>.<lambda>(x)
    322     alias = com._builtin_table_alias[func]
    323     warn_alias_replacement(self, orig_func, alias)
--> 324 f = lambda x: func(x, *args, **kwargs)
    326 obj = self._obj_with_exclusions
    327 result = self._grouper.agg_series(obj, f)

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/shapely/decorators.py:77, in multithreading_enabled.<locals>.wrapped(*args, **kwargs)
     75     for arr in array_args:
     76         arr.flags.writeable = False
---> 77     return func(*args, **kwargs)
     78 finally:
     79     for arr, old_flag in zip(array_args, old_flags):

File ~/dev/pysal/.pixi/envs/default/lib/python3.12/site-packages/shapely/set_operations.py:509, in coverage_union_all(geometries, axis, **kwargs)
    505 # create_collection acts on the inner axis
    506 collections = lib.create_collection(
    507     geometries, np.intc(GeometryType.GEOMETRYCOLLECTION)
    508 )
--> 509 return lib.coverage_union(collections, **kwargs)

GEOSException: TopologyException: side location conflict at 575350.8642359447 115811.18337658927. This can occur if the input geometry is invalid.
```

[files here](https://github.com/user-attachments/files/19129503/Archive.zip)

No way around this at the moment. [HIDDEN]

### Additional contract requirements

- For the reported failure case, `voronoi_frames` must complete and return its Voronoi output instead of propagating the GEOS topology error.
