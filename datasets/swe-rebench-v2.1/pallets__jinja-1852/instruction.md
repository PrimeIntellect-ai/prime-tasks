f-string sytax error when importing macro in a template which filename is also a template
With this template structure:
```
/templates/
+- {% jinja expr %}.jinja
+- macro_file.jina
```
When `{% jinja expr %}.jinja` imports a macro using 'from "macro_file.jinja" import my_macro' syntax, Environment.render fails with `SyntaxError: f-string: invalid syntax` error message.

[HIDDEN]
```python
if l_0_print_helo is missing:
        [HIDDEN][HIDDEN].txt.jinja') does not export the requested name 'print_helo'", name='print_helo')
```

Couldn't reproduce the error using `import "macro_file.jinja" as m` syntax.

Environment:

- Python 3.10.7
- Jinja 3.1.2

### Additional contract requirements

- A template whose filename contains f-string-like brace syntax must not fail with a Python `SyntaxError` for invalid f-string syntax when it uses a `from ... import ...` statement.
- Braces and their contents in such a filename must be treated as literal filename characters, not evaluated as Python names; rendering must not fail with a `NameError` caused by the filename contents.
