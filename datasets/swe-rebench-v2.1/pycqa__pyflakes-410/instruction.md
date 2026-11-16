crash: AttributeError: 'Module' object has no attribute 'parent'
9dd73ec54411a563410872b47e76f0f89f34ecfe seems to introduce a bug that causes pyflakes to crash on this code:

```python3
class foo:
    pass


async def func(foo: foo):
    pass
```

**backtrace:**
```
$ venv/bin/pyflakes foo.py
Traceback (most recent call last):
  File "venv/bin/pyflakes", line 11, in <module>
    sys.exit(main())
  File "venv/lib/python3.7/site-packages/pyflakes/api.py", line 207, in main
    warnings = checkRecursive(args, reporter)
  File "venv/lib/python3.7/site-packages/pyflakes/api.py", line 156, in checkRecursive
    warnings += checkPath(sourcePath, reporter)
  File "venv/lib/python3.7/site-packages/pyflakes/api.py", line 99, in checkPath
    return check(codestr, filename, reporter)
  File "venv/lib/python3.7/site-packages/pyflakes/api.py", line 74, in check
    w = checker.Checker(tree, filename)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 579, in __init__
    self.runDeferred(self._deferredFunctions)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 616, in runDeferred
    handler()
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 1354, in runFunction
    self.handleChildren(node, omit='decorator_list')
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 957, in handleChildren
    self.handleNode(node, tree)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 1004, in handleNode
    handler(node)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 1379, in ARGUMENTS
    self.handleChildren(node, omit=('defaults', 'kw_defaults'))
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 957, in handleChildren
    self.handleNode(node, tree)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 1004, in handleNode
    handler(node)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 1388, in ARG
    self.addBinding(node, Argument(node.arg, self.getScopeNode(node)))
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 784, in addBinding
    parent_stmt = self.getParent(value.source)
  File "venv/lib/python3.7/site-packages/pyflakes/checker.py", line 722, in getParent
    node = node.parent
AttributeError: 'Module' object has no attribute 'parent'
```

**version:**

  * debian/unstable
  * python3.7 (from debian)
  * pyflakes 066ba4a93c1077f9154d6ff3806fe1e3a66843a1
