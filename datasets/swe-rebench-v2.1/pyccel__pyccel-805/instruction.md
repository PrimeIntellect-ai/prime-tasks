Bug in semantic parser when sliced array is modified in function call
**Describe the bug**

Pull request #716 introduced a regression bug at the semantic stage, which appears when these conditions are met:
- One function modifies an input array (which has `intent(inout)`);
- Another function calls the first function passing a sliced array to it;
- Both functions are pyccelized.

**To Reproduce**

Let's consider file `test_view.py`:

```python
import numpy as np

def f(x : 'float[:]'):
    x[0] = 1

def g():
    x = np.zeros(3)
    f(x[:])
    print(x)
```

Pyccel fails during the semantic stage:
```bash/fortran/c
$ pyccel test_view.py
Traceback (most recent call last):
  File "/home/yamanguc/.local/bin/pyccel", line 11, in <module>
    load_entry_point('pyccel', 'console_scripts', 'pyccel')()
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/commands/console.py", line 258, in pyccel
    folder        = args.output)
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/codegen/pipeline.py", line 247, in execute_pyccel
    parser.annotate(**settings)
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/parser.py", line 191, in annotate
    **settings)
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 173, in __init__
    self.annotate()
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 209, in annotate
    ast = self._visit(ast, **settings)
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 802, in _visit
    obj = getattr(self, annotation_method)(expr, **settings)
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 838, in _visit_CodeBlock
    ls = [self._visit(i, **settings) for i in expr.body]
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 838, in <listcomp>
    ls = [self._visit(i, **settings) for i in expr.body]
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 802, in _visit
    obj = getattr(self, annotation_method)(expr, **settings)
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 2593, in _visit_FunctionDef
    assigned     = [a.name for a in all_assigned if a.rank > 0]
  File "/home/yamanguc/Library/PYCCEL/pyccel/pyccel/parser/semantic.py", line 2593, in <listcomp>
    assigned     = [a.name for a in all_assigned if a.rank > 0]
AttributeError: 'IndexedElement' object has no attribute 'name'

```

**Expected behavior**

Pyccel should be able to process file `test_view.py` without any problems, and a call to `g()` should print `[1, 0, 0]`.

**Language**

This bug is independent of the target language, as it happens during the semantic stage.
