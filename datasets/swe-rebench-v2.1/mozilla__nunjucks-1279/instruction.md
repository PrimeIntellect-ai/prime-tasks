Implement select/reject
These exists in jinja and is a pretty good way to exclude something from array iteration. I'm working on a patch.

### Additional contract requirements

- Provide `select` and `reject` filters for filtering a sequence using a named registered Nunjucks test. An optional additional argument is passed to that test for each item.
- `select` keeps items for which the test returns true; `reject` keeps items for which it does not.
- If no test is specified, use truthiness: `select` keeps truthy items and `reject` keeps falsy items.
