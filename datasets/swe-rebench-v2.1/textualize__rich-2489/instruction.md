[REQUEST] Allow delimiters when using `pprint(..., max_depth=...)`
**How would you improve Rich?**

Currently, when pretty printing a nested object, we can set the max depth to simplify the object display:
```python
>>> from rich.pretty import pprint
>>> pprint({"a": {"b": {"c": "d"}}, "e": ["f", "g"]}, max_depth=1)
{'a': ..., 'e': ...}
```

However, by using ellipsis like this, we obscure the information about the data type of "a". In contrast, Python's built-in `pprint` module adds delimiters around the ellipsis, to differentiate between a list and a dict:
```python
>>> import pprint
>>> pprint.pprint({"a": {"b": {"c": "d"}}, "e": ["f", "g"]}, depth=1)
{'a': {...}, 'e': [...]}
```

Notice how, with only 4 extra characters, we have significantly more information about the eluded structure.

I would like to propose that we add a new argument to `pprint()` such as `max_depth_delims: bool`, which when True, would enable the behaviour above.

**What problem does it solve for you?**

When I use `max_depth` in tutorial or example, it's because I don't want unnecessary detail taking up a large amount of screen real estate. However I still want my users to understand that there *is* additional detail available, and to give them a hint as to what kind of data is nested further in the tree, and how to access it. Adding these delimiters nicely enable this compromise.

### Additional contract requirements

- Delimiter rendering is the default when `max_depth` truncates a value; no enabling option is required. For `d = {"foo": {"fob": {"a": [1, 2, 3], "b": {"z": "x", "y": ["a", "b", "c"]}}}}`, `pretty_repr(d, max_depth=0)`, `pretty_repr(d, max_depth=1)`, `pretty_repr(d, max_depth=2)`, and `pretty_repr(d, max_depth=3)` return, respectively, `"{...}"`, `"{'foo': {...}}"`, `"{'foo': {'fob': {...}}}"`, and `"{'foo': {'fob': {'a': [...], 'b': {...}}}}"`. `pretty_repr(d, max_width=100, max_depth=4)` returns `"{'foo': {'fob': {'a': [1, 2, 3], 'b': {'z': 'x', 'y': [...]}}}}"`. Truncating `{"unit": StockKeepingUnit("a", "b", 1.0, "c", ["d", "e"])}` at depth 1 returns `"{'unit': StockKeepingUnit(...)}"`, and `pretty_repr(Foo(foo=Bar(bar=Foo(foo=[]))), max_depth=2)` returns `"Foo(foo=Bar(bar=Foo(...)))"`.
