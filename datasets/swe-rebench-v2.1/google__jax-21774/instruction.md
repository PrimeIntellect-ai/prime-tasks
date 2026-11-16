Allow for `is_leaf` in tree_all
`tree_all` just [HIDDEN], which does allow for a `is_leaf` function. It seems logical to allow for tree all to [HIDDEN] (since the user might define a custom object which overrides the bool and want that to be considered). If this is something of interest I can make a PR.

### Additional contract requirements

- `tree_all` must accept an optional `is_leaf` predicate and use it to determine which values are evaluated.
- `jax.tree.all` and `jax.tree_util.tree_all` must both expose this optional behavior.
