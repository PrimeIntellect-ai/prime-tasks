Allow overwriting registered rewrite
### Description

PyTensor raises if you try to register the same rewrite twice. This is annoying when developing rewrites in an interactive environment, forcing constant restart of the interpreter. Would be nice to add an `overwrite_existing` flag to allow replacing the pre-existing rewrite by the new one. The logic of how rewrites are registered is pretty messy though, so it may require some work.

```python
from pytensor.graph.rewriting.basic import node_rewriter
from pytensor.tensor.rewriting.basic import register_canonicalize

@node_rewriter(None)
def my_rewrite():
    pass

register_canonicalize(my_rewrite)
register_canonicalize(my_rewrite)  # ValueError: The tag 'my_rewrite' is already present in the database.
```
