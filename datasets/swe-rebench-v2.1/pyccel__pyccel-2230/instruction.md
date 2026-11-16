Variable already exists when using type annotation and result annotation
### Describe the bug
When we use a type annotation for both the result type and the variable returned as the result, Pyccel thinks that the type has been declared twice. This leads to an error.

### To Reproduce
Provide code to reproduce the behaviour:
```python
def f() -> 'int':
    result_0001 : 'int'
    return result_0001
```
The following code also causes the error but reports it more cleanly:
```python
def f() -> 'int':
    result_0001 : 'int' = 1
    return result_0001
```

### Error details
Provide the generated code, or the error message:
```
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 4551, in _visit_FunctionDef
    body = self._visit(expr.body)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2373, in _visit
    raise err
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2361, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2712, in _visit_CodeBlock
    self.scope.insert_variable(line[0])
  File "/home/emily/Code/pyccel/pyccel/parser/scope.py", line 355, in insert_variable
    raise RuntimeError(f'New variable {name} already exists in scope')
RuntimeError: New variable result_0001 already exists in scope
```
with `result_0001 : 'int' = 1`:
```
ERROR at annotation (semantic) stage
pyccel:
   File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2361, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2705, in _visit_CodeBlock
    line = self._visit(b)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 2361, in _visit
    obj = getattr(self, annotation_method)(expr)
  File "/home/emily/Code/pyccel/pyccel/parser/semantic.py", line 3442, in _visit_Assign
    errors.report(e, symbol=expr, severity='error')
  File "/home/emily/Code/pyccel/pyccel/errors/errors.py", line 345, in report
    traceback = ''.join(tb.format_stack(limit=5))
|error [semantic]: tmp.py [3,4]| New variable result_0001 already exists in scope (<pyccel.ast.variable.AnnotatedPyccelSymbol object at 0x7416a6fb90d0> := Literal(0))
```

### Expected behavior
This should be allowed

### Language
All languages

### Additional context
Blocking #2217
