Filters decorated with @async_variant are not pickleable
<!--
This issue tracker is a tool to address bugs in Jinja itself. Please
use Pallets Discord or Stack Overflow for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->
The [`jinja2.async_utils.async_variant`][async_variant] decorator puts the wrong `__name__` and `__qualname__` on the decorated function.  One result of this is that functions which it decorates are not pickleable.

<!--
Describe how to replicate the bug.

Include a minimal reproducible example that demonstrates the bug.
Include the full traceback if there was an exception.
-->
Here's a doctest script which illustrates the issue.
```pycon
>>> import pickle
>>> import jinja2.filters

>>> pickle.dumps(jinja2.filters.do_first)
Traceback (most recent call last):
    ...
_pickle.PicklingError: Can't pickle <function sync_do_first at 0x...>: it's not the same object as jinja2.filters.sync_do_first

# Here's the crux:
>>> jinja2.filters.do_first.__name__
'sync_do_first'
```

[async_variant]: https://github.com/pallets/jinja/blob/09907ef37891be76ab0a1a3dc1a3f7df667db959/src/jinja2/async_utils.py#L11

<!--
Describe the expected behavior that should have happened but didn't.
-->

Environment:

- Python version: 3.10 — but I don't think that's important
- Jinja version: git main (09907ef37891be76ab0a1a3dc1a3f7df667db959) — but I think this affects all versions >= 3

I will submit a PR with one possible fix shortly.
