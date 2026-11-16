Can't call return in for loop
### Describe the bug
When calling `return` in a for loop, the function is found in an enclosing scope not the current scope. This leads to a traceback error when checking pointers and targets.

### To Reproduce
Provide code to reproduce the behavior:
```python
def f(n : int):
    for i in range(1000):
        if i > n:
            return 1
    return 0
```

### Error details
Provide the generated code, or the error message:
```
Traceback (most recent call last):
  File "/home/emily/.local/bin/pyccel", line 8, in <module>
    sys.exit(pyccel())
  File "/home/emily/Code/pyccel/pyccel/commands/console.py", line 266, in pyccel
    execute_pyccel(filename,
  File "/home/emily/Code/pyccel/pyccel/codegen/pipeline.py", line 234, in execute_pyccel
    parser.annotate(verbose = verbose)
  File "/home/emily/Code/pyccel/pyccel/parser/parser.py", line 160, in annotate
    parser = SemanticParser(self._syntax_parser,
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 245, in __init__
    self.annotate()
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 318, in annotate
    ast = self._visit(ast)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1947, in _visit_Module
    body = self._visit(expr.program).body
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2214, in _visit_CodeBlock
    line = self._visit(b)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3808, in _visit_FunctionDef
    body = self._visit(expr.body)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2214, in _visit_CodeBlock
    line = self._visit(b)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3335, in _visit_For
    body = self._visit(expr.body)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2214, in _visit_CodeBlock
    line = self._visit(b)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3602, in _visit_If
    args = [self._visit(i) for i in expr.blocks]
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3602, in <listcomp>
    args = [self._visit(i) for i in expr.blocks]
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3591, in _visit_IfSection
    body = self._visit(expr.body)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2214, in _visit_CodeBlock
    line = self._visit(b)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 1935, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3695, in _visit_Return
    self._check_pointer_targets(results)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 654, in _check_pointer_targets
    [HIDDEN]
KeyError: 'f'
```

### Expected behavior
[HIDDEN]

### Language
All languages

### Additional context
Breaks the Bellman Ford benchmark

### Additional contract requirements

- A `return` inside a `for` loop, including one nested in a conditional, must return from its enclosing function without triggering a traceback in all supported languages.
