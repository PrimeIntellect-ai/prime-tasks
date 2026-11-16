Error AttributeError: 'ClassScope' object has no attribute 'indirect_assignments' encountered on `3.3.1`
Hello,
When running flake8 `7.2.0` with pyflake `3.3.1`, we encountered the following errors
```
flake8 --version
7.2.0 (mccabe: 0.7.0, pycodestyle: 2.13.0, pyflakes: 3.3.1) CPython 3.11.9 on
Linux
+ flake8 -v DEPRECATED tests
flake8.checker            MainProcess    121 INFO     Making checkers
flake8.checker            ForkPoolWorker-1   1373 CRITICAL Plugin pyflakes[F] raised an unexpected exception
Traceback (most recent call last):
  File "/code/venv/lib/python3.11/site-packages/flake8/checker.py", line 342, in run_check
    return plugin.obj(**arguments, **params)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/code/venv/lib/python3.11/site-packages/flake8/plugins/pyflakes.py", line 73, in __init__
    super().__init__(
  File "/code/venv/lib/python3.11/site-packages/pyflakes/checker.py", line 757, in __init__
    self.handleChildren(tree)
  File "/code/venv/lib/python3.11/site-packages/pyflakes/checker.py", line 1222, in handleChildren
    self.handleNode(node, tree)
  File "/code/venv/lib/python3.11/site-packages/pyflakes/checker.py", line 1270, in handleNode
    handler(node)
  File "/code/venv/lib/python3.11/site-packages/pyflakes/checker.py", line 2010, in CLASSDEF
    self.handleNode(stmt, node)
  File "/code/venv/lib/python3.11/site-packages/pyflakes/checker.py", line 1270, in handleNode
    handler(node)
  File "/code/venv/lib/python3.11/site-packages/pyflakes/checker.py", line 1855, in GLOBAL
    self.scope.indirect_assignments[node_name] = node
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'ClassScope' object has no attribute 'indirect_assignments'
flake8.main.application   MainProcess   1385 INFO     Finished running
flake8.main.application   MainProcess   1385 INFO     Reporting errors
flake8.main.application   MainProcess   1385 INFO     Found a total of 0 violations and reported 0
```
It seems caused by the change in this commit https://github.com/PyCQA/pyflakes/commit/cadcd60a70c118c1d8b6dc8c09e53dc8f32b1666
As only `FunctionScope` has the attr `indirect_assignments`.

### Additional contract requirements

- In class bodies, handle `global` and `nonlocal` declarations without raising an exception. Report `UnusedIndirectAssignment` when a declared name is not assigned in that class body, and do not report it when the name is assigned there.
