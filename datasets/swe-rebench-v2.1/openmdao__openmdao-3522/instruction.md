Add ability to return a copy with get_val
### Desired capability or behavior.

Depending on the options passed, get_val may currently return a view into an internal OpenMDAO vector.
This can have some unexpected behavior when repeatedly using set_val/get val when interrogating a system.

The simple workaround is to use `np.copy(prob.get_val(...))`, but its not obvious that users may need to do this.
We should add an argument `copy=False` by default.  This will be slightly less verbose for the user, and its presence in the options will document that it is sometimes necessary for users to use.

There's some argument to be made that copying should be the default behavior, but leaving it False for now will maintain backwards compatibility.

### Associated POEM

_No response_

### Additional contract requirements

- `Problem.get_val` (public method of `openmdao.core.problem.Problem`) accepts a `copy` keyword argument that defaults to `False`. When `copy=True`, the returned value is an independent deep copy, so mutating it does not change the value stored in the Problem; when `copy=False` (the default), the existing behavior of returning a reference to the stored value is preserved.
- `System.get_val` (public method of `openmdao.core.system.System`) accepts a `copy` keyword argument that defaults to `False`, with the same behavior: `copy=True` returns an independent deep copy and `copy=False` preserves the existing reference-returning behavior.
