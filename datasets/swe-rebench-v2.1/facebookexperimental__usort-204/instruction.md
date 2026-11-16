AssertionError when formatting semicolon-delimited import lines
Originally noticed via omnilib/ufmt#115:

AssertionError is raised when formatting a file with multiple statements on a line that includes an import. The following example code will trigger this error in 1.0.4:

```python
import sys; print(sys)
```

```shell-session
$ usort -V
usort, version 1.0.4

$ usort check foo.py
Error sorting foo.py:
Would sort foo.py
```

As seen from the API:

```ipython
Python 3.9.9 (main, Nov 28 2021, 12:38:04)
Type 'copyright', 'credits' or 'license' for more information
IPython 8.5.0 -- An enhanced Interactive Python. Type '?' for help.

In [1]: import usort

In [2]: from pathlib import Path

In [3]: foo = Path("foo.py")

In [4]: content = b"import sys; print(sys)\n\n"

In [5]: config = usort.Config()

In [6]: result = usort.usort(content, config, foo)

In [7]: result.error
Out[7]: AssertionError()

In [8]: print(result.trace)
Traceback (most recent call last):
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/usort/api.py", line 33, in usort
    new_mod = sorter.sort_module()
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/usort/sorting.py", line 305, in sort_module
    new_module = self.wrapper.visit(self.transformer)
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/libcst/metadata/wrapper.py", line 204, in visit
    return self.module.visit(visitor)
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/libcst/_nodes/module.py", line 90, in visit
    result = super(Module, self).visit(visitor)
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/libcst/_nodes/base.py", line 237, in visit
    leave_result = visitor.on_leave(self, with_updated_children)
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/libcst/_visitors.py", line 71, in on_leave
    updated_node = leave_func(original_node, updated_node)
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/usort/sorting.py", line 348, in leave_Module
    sorted_body = self.sorter.find_and_sort_blocks(
  File "/Users/amethyst/workspace/ufmt/.venv/lib/python3.9/site-packages/usort/sorting.py", line 278, in find_and_sort_blocks
    blocks = list(self.sortable_blocks(body))
  [HIDDEN]
```

### Additional contract requirements

- Formatting a file with multiple statements on a line that includes an import must not raise an AssertionError.
