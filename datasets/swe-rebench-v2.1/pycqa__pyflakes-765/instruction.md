Regression with version 3.0 ('bool' object is not subscriptable)
Hello! I found a regression with version 3.0

This snippet:
```
test: int

test.__dict__


def fn():
    test = 1
```

Raises the following exception with version 3.0.1:
```
Traceback (most recent call last):
  File "/opt/homebrew/bin/pyflakes", line 8, in <module>
    sys.exit(main())
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/api.py", line 182, in main
    warnings = checkRecursive(args, reporter)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/api.py", line 127, in checkRecursive
    warnings += checkPath(sourcePath, reporter)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/api.py", line 71, in checkPath
    return check(codestr, filename, reporter)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/api.py", line 47, in check
    w = checker.Checker(tree, filename=filename)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 789, in __init__
    self.runDeferred(self._deferredFunctions)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 832, in runDeferred
    handler()
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1998, in runFunction
    self.handleChildren(node, omit=['decorator_list', 'returns'])
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1238, in handleChildren
    self.handleNode(node, tree)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1283, in handleNode
    handler(node)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1238, in handleChildren
    self.handleNode(node, tree)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1283, in handleNode
    handler(node)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1889, in NAME
    self.handleNodeStore(node)
  File "/opt/homebrew/lib/python3.10/site-packages/pyflakes/checker.py", line 1163, in handleNodeStore
    if used and used[0] is self.scope and name not in self.scope.globals:
TypeError: 'bool' object is not subscriptable
```

But it is correctly handled by version 2.5.0, that returns the correct errors:

```
test.py:3:1: undefined name 'test'
test.py:7:5: local variable 'test' is assigned to but never used
```

The snippet does not cause exceptions when any part of it is removed (for example the type annotation or the `test.__dict__` or the assignment in the function)
