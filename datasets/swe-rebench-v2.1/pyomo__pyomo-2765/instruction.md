Indexing error
Hi, when trying to add an extra constraint I get the following error:
raise DeveloperError(
pyomo.common.errors.DeveloperError: Internal Pyomo implementation error:
        'Unknown problem encountered when trying to retrieve index for component assign_to_open_cstr'
        Please report this to the Pyomo Developers.

This happens due to the following code:
m.travel_pairs = pyo.Set(initialize=[(i, j) for i in m.set1 for j in m.set2])
m.assign_to_open_cstr = pyo.Constraint(m.pairs, rule=assign_to_open_cstr)
And then later I try to add constraints:
for (i,j) in new_pairs:
        m.assign_to_open_cstr.add(expr=assign_to_open_cstr(m,i,j), index=[i,j])

I think the way I format the index might just be wrong, but since the error told me to report this, this what I am doing.

### Additional contract requirements

- `Var.__getitem__(index)` accepts a scalar key, a list containing a scalar key, a list representing a tuple of keys, or a tuple of keys, and returns the corresponding variable element. Equivalent forms return the same object (for example, `m.x[[1]]` is `m.x[1]` and `m.y[[1, 2]]` is `m.y[1, 2]`).
- `Var.__getitem__(index)` raises `TypeError` when the index is an unhashable type such as a `dict`, and raises `KeyError` when the index is not present in the component's index set.
- `Var.__setitem__(index, value)` accepts the same index forms, assigns `value` to the targeted variable element, and returns the same variable element for repeated indexing of the same index. It raises `TypeError` for an unhashable index and `KeyError` for an index not present in the component's index set.
- Adding a constraint to an indexed `Constraint` with a list-form index (for example, `m.c.add(expr=..., index=[i, j])`) succeeds when the corresponding tuple index is valid for the component.
