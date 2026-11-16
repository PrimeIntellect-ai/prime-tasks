Retrieving sets multiple times doesn't work
### Describe the bug
If the same set is used twice in a Fortran translation then a traceback is seen

### To Reproduce
Provide code to reproduce the behavior:
```python
def update_multiple():
    a = {1, 2, 3}
    a.update({4, 5})

def set_union():
    a = {1,2,3,4,5}
    b = {4,5,6}
    c = a.union(b)
```

### Error details
Provide the generated code, or the error message:
```bash/fortran/c
<pre>Traceback (most recent call last):
  File &quot;/home/emily/.local/bin/pyccel&quot;, line 8, in &lt;module&gt;
    sys.exit(pyccel())
  File &quot;/home/emily/Code/pyccel/pyccel/commands/console.py&quot;, line 266, in pyccel
    execute_pyccel(filename,
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/pipeline.py&quot;, line 263, in execute_pyccel
    fname, prog_name = codegen.export(fname)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/codegen.py&quot;, line 220, in export
    code = self._printer.doprint(self.ast)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/codeprinter.py&quot;, line 53, in doprint
    lines = self._print(expr).splitlines(True)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/codeprinter.py&quot;, line 121, in _print
    obj = getattr(self, print_method)(expr)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 825, in _print_Module
    func_strings += [&apos;&apos;.join([sep, self._print(i), sep]) for i in expr.funcs]
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 825, in &lt;listcomp&gt;
    func_strings += [&apos;&apos;.join([sep, self._print(i), sep]) for i in expr.funcs]
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/codeprinter.py&quot;, line 121, in _print
    obj = getattr(self, print_method)(expr)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 2439, in _print_FunctionDef
    body_code = self._print(expr.body)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/codeprinter.py&quot;, line 121, in _print
    obj = getattr(self, print_method)(expr)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 2005, in _print_CodeBlock
    line = self._print(b)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/codeprinter.py&quot;, line 121, in _print
    obj = getattr(self, print_method)(expr)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 2021, in _print_Assign
    return self._print(rhs)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/codeprinter.py&quot;, line 121, in _print
    obj = getattr(self, print_method)(expr)
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 1351, in _print_SetUnion
    self.add_import(self._build_gFTL_extension_module(expr_type))
  File &quot;/home/emily/Code/pyccel/pyccel/codegen/printing/fcode.py&quot;, line 690, in _build_gFTL_extension_module
    type_module = matching_expr_type.source_module
AttributeError: &apos;HomogeneousSetType&apos; object has no attribute &apos;source_module&apos;
</pre>
```

### Expected behavior
The handling of `_build_gFTL_extension_module` should be fixed

### Language
Fortran
