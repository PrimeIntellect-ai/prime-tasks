`typehints_defaults` does not work when missing python3 sytle type hints
Given function signature
```python
def grid_archive_heatmap(archive, ax=None, ... )
```
and setting `typehints_defaults = "comma" ("braces", "braces-after")` . `sphinx-autodoc-typehints` does not correctly add a "default=" clause for the argument `ax` in the documentation.

This problem was encountered at https://github.com/icaros-usc/pyribs/pull/204.
