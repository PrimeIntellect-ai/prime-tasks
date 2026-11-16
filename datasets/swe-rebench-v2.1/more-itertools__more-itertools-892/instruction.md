Add a strict option to sort_together()
A *strict* option would detect data size mismatches. This would avoid silently dropping data:

```
>>> iterables = [(4, 3, 2, 1), ('a', 'b', 'c')]
>>> sort_together(iterables)
[(2, 3, 4), ('c', 'b', 'a')]
```

### Additional contract requirements

- `sort_together` accepts a keyword argument `strict` that defaults to `False`.
- When `strict` is `False`, the iterables are sorted together only up to the length of the shortest iterable, and any extra trailing elements of longer iterables are dropped.
- When `strict` is `True` and the supplied iterables do not all have the same length, `more_itertools.UnequalIterablesError` is raised.
- When `strict` is `True` and all supplied iterables have the same length, sorting succeeds and returns all rows in the requested sorted order.
