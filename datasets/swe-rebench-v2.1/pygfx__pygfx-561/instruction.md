`Geometry` accepts arrays with size 0
Came across this when working with real data, I have empty arrays with a shape, but `size = 0`.

It is possible to create this line, but methods that rely on computing the bounding box will fail since numpy raises an exception if the array size is zero.

I have two ideas:
1. Raise an exception if an array of size 0 is given to `Geometry`.
2. Allow Geometry with zero sized arrays, but ignore them when computing the bounding box. (I think I like this option)

Happy to PR for either :)

This may be seen as an edge case, but libraries like matplotlib handle this just fine, it seems like it's using option #2. It doesn't raise an exception when creating a line with an empty array and displays a blank plot. If multiple lines are plotted it can still display the rest w.r.t. the bounding box of all the lines in the plot, so it must be ignoring the zero-size array's bounding box.

Example:

```python
import pygfx as gfx

positions = np.reshape([], (0, 3)).astype(np.float32)
print(f"shape: {positions.shape}, size: {positions.size}")
# shape: (0, 3), size: 0

line = gfx.Line(
    gfx.Geometry(positions=positions),
    gfx.LineMaterial(thickness=3, color="w"),
)
# everything works up to this point

# relies on `camera.show_object`, so it will not work.
gfx.show(line)
```

```python
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[111], line 11
      4 print(f"shape: {positions.shape}, size: {positions.size}")
      6 line = gfx.Line(
      7     gfx.Geometry(positions=positions),
      8     gfx.LineMaterial(thickness=3, color="w"),
      9 )
---> 11 gfx.show(line)

File ~/repos/pygfx/pygfx/utils/show.py:271, in show(object, up, canvas, renderer, controller, camera, before_render, after_render, draw_function)
    210 def show(
    211     object: WorldObject,
    212     up=None,
   (...)
    220     draw_function=None,
    221 ):
    222     """Display a WorldObject
    223
    224     This function provides you with the basic scaffolding to visualize a given
   (...)
    266
    267     """
    269     Display(
    270         canvas, renderer, controller, camera, before_render, after_render, draw_function
--> 271     ).show(object, up)

File ~/repos/pygfx/pygfx/utils/show.py:192, in Display.show(self, object, up)
    190 else:
    191     self.camera = PerspectiveCamera(70, 4 / 3)
--> 192     self.camera.show_object(object, up=up, scale=1.4)
    193 if custom_scene:
    194     cam_has_light = next(self.camera.iter(lambda x: isinstance(x, Light)), None)

File ~/repos/pygfx/pygfx/cameras/_perspective.py:367, in PerspectiveCamera.show_object(self, target, view_dir, up, scale)
    365 # Get bounding sphere from target
    366 if isinstance(target, WorldObject):
--> 367     bsphere = target.get_world_bounding_sphere()
    368     if bsphere is None:
    369         raise ValueError(
    370             "Given target does not have a bounding sphere, you should probably just provide a sphere (x, y, z, r) yourself."
    371         )

File ~/repos/pygfx/pygfx/objects/_base.py:510, in WorldObject.get_world_bounding_sphere(self)
    501 def get_world_bounding_sphere(self):
    502     """Bounding Sphere in world space.
    503
    504     Returns
   (...)
    508
    509     """
--> 510     return la.aabb_to_sphere(self.get_world_bounding_box())

File ~/repos/pygfx/pygfx/objects/_base.py:499, in WorldObject.get_world_bounding_box(self)
    490 def get_world_bounding_box(self):
    491     """Axis aligned bounding box in world space.
    492
    493     Returns
   (...)
    497
    498     """
--> 499     return la.aabb_transform(self.get_bounding_box(), self.world.matrix)

File ~/repos/pygfx/pygfx/objects/_base.py:472, in WorldObject.get_bounding_box(self)
    470     partial_aabb[idx] = la.aabb_transform(aabb, trafo)
    471 if include_self:
--> 472     partial_aabb[-1] = self.geometry.bounding_box()
    474 final_aabb = np.zeros((2, 3), dtype=float)
    475 final_aabb[0] = np.min(partial_aabb[:, 0, :], axis=0)

File ~/repos/pygfx/pygfx/geometries/_base.py:119, in Geometry.bounding_box(self)
    117     return self._aabb
    118 pos = self.positions.data
--> 119 self._aabb = np.array([np.nanmin(pos, axis=0), np.nanmax(pos, axis=0)])
    120 # If positions contains xy, but not z, assume z=0
    121 if self._aabb.shape[1] == 2:

File <__array_function__ internals>:180, in nanmin(*args, **kwargs)

File ~/python-venvs/mescore/lib/python3.11/site-packages/numpy/lib/nanfunctions.py:343, in nanmin(a, axis, out, keepdims, initial, where)
    338     kwargs['where'] = where
    340 if type(a) is np.ndarray and a.dtype != np.object_:
    341     # Fast, but not safe for subclasses of ndarray, or object arrays,
    342     # which do not implement isnan (gh-9009), or fmin correctly (gh-8975)
--> 343     res = np.fmin.reduce(a, axis=axis, out=out, **kwargs)
    344     if np.isnan(res).any():
    345         warnings.warn("All-NaN slice encountered", RuntimeWarning,
    346                       stacklevel=3)

ValueError: zero-size array to reduction operation fmin which has no identity
```

### Additional contract requirements

- `Geometry.get_bounding_box()` returns the axis-aligned bounding box as an array of shape `(2, 3)` (the lowest and the highest corner), or `None` when the geometry has no finite positions. It supports geometries defined by vertex positions as well as geometries defined by grid data.
- `Geometry.get_bounding_sphere()` returns a bounding sphere as an array of shape `(4,)` in the form `(x, y, z, radius)` that contains the geometry's finite positions, or `None` when the geometry has no finite positions.
- `WorldObject.get_bounding_box()` returns the combined axis-aligned bounding box of the object's own geometry and its descendants as an array of shape `(2, 3)`, or `None` when nothing contributes a box.
- `WorldObject.get_world_bounding_box()` returns the object's bounding box transformed into world space as an array of shape `(2, 3)`, or `None` when the object has no bounding box.
- `WorldObject.get_world_bounding_sphere()` returns a world-space bounding sphere as an array of shape `(4,)` in the form `(x, y, z, radius)`, or `None` when the object has no bounding box.
