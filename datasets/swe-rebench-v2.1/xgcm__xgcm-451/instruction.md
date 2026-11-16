[BUG] Can't apply grid ufunc with padding if axis position doesn't change
I realised that I overlooked quite an important case: currently if you try to apply a grid ufunc which pads along an axis but still returns a variable which has that same `axis:position` pair as the input, `xr.apply_ufunc` will throw an error. For example whilst this works:

```python
@as_grid_ufunc("(X:center)->(X:left)", boundary_width={"X": (1, 0)})
def diff_center_to_left(a):
    return a[..., 1:] - a[..., :-1]
```

this does not:

```python
@as_grid_ufunc("(X:center)->(X:center)", boundary_width={"X": (2, 0)})
def diff_center_to_center_second_order(a):
    return 0.5 * (a[..., 2:] - a[..., :-2])
```

The latter throws an error like

```
ValueError: size of dimension 'depth_c' on inputs was unexpectedly changed by applied function from 11 to 9.
Only dimensions specified in ``exclude_dims`` with xarray.apply_ufunc are allowed to change size.
```

The reason is that the dimensions of the output variable are set by the grid positions in the signature - in the first case we pad a dimension to be longer, then act on it with `xr.apply_ufunc` and want the output to be shorter _along a different dimension_, whereas in the second case we pad a dimension to be longer, then act on it with `xr.apply_ufunc` and want the output to be shorter _along that same dimension_.

There are potentially two ways to fix this:
1) Do something clever with renaming dimensions to have temporary names whilst inside `xr.apply_ufunc`, so xarray doesn't realise there is a conflict in sizes,
2) Move the padding inside the ufunc as described in #436.

---

This bug is currently what's stopping me from computing vorticity of LLC data @rabernat FYI, because the simplest grid ufunc for that looks like this (see #436)

```python
def diff(a, axis):
    def _diff(a):
        return a[..., 1:] - a[..., :-1]

    return np.apply_along_axis(_diff, axis, a)


@as_grid_ufunc("(lon:left,lat:center),(lon:center,lat:left)->(lon:left,lat:left)",
               boundary_width={"lon": (1, 0), "lat": (1, 0)})
def vort(u, v):
    """This needs to return an array 1 element smaller along both axis -1 & -2."""
    u_trimmed = u[..., 1:]
    v_trimmed = v[..., 1:, :]

    return (
        diff(v_trimmed, axis=-1)
        - diff(u_trimmed, axis=-2)
    )
```
which has `lon:left` and `lat:left` on both inputs and outputs.
