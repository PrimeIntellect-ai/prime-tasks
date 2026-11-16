Backtrace due to incompatible types in shapes
### Describe the bug
Backtrace due to incompatible types in shapes. [HIDDEN] This causes problems later if the variable is sliced.

### To Reproduce
Provide code to reproduce the behavior:
```python
import numpy as np

if __name__ == '__main__':
    n = 4
    b = True
    if b:
        self_knots = np.zeros(n)
    else:
        self_knots = np.zeros(n+2)
    knots = self_knots[1:-1]
```

### Error details
Provide the generated code, or the error message:
```bash/fortran/c
Traceback (most recent call last):
  File "/home/emily/.local/bin/pyccel", line 8, in <module>
    sys.exit(pyccel())
  File "/home/emily/Code/pyccel/pyccel/commands/console.py", line 266, in pyccel
    execute_pyccel(filename,
  File "/home/emily/Code/pyccel/pyccel/codegen/pipeline.py", line 232, in execute_pyccel
    parser.annotate(verbose = verbose)
  File "/home/emily/Code/pyccel/pyccel/parser/parser.py", line 173, in annotate
    parser = SemanticParser(self._syntax_parser,
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 261, in __init__
    self.annotate()
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 318, in annotate
    ast = self._visit(ast)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2279, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2332, in _visit_Module
    body += self._visit(expr.program.body).body
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2279, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2604, in _visit_CodeBlock
    line = self._visit(b)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2279, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3381, in _visit_Assign
    rhs = self._visit(rhs)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2279, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2751, in _visit_IndexedElement
    return self._extract_indexed_from_var(var, args, expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 892, in _extract_indexed_from_var
    for arg in var[indices].indices:
  File "/home/emily/Code/pyccel/pyccel/ast/variable.py", line 528, in __getitem__
    return IndexedElement(self, *args)
  File "/home/emily/Code/pyccel/pyccel/ast/variable.py", line 760, in __init__
    self._shape = tuple(new_shape) + base.shape[rank:]
TypeError: can only concatenate tuple (not "list") to tuple
```

### Expected behavior
[HIDDEN]

### Language
Not language specific

### Additional context
Seen in PyGyro

### Additional contract requirements

When array allocations in different conditional branches have different shapes, slicing the resulting array must work. A variable's shape metadata must remain tuple-valued when its shape is made changeable.
