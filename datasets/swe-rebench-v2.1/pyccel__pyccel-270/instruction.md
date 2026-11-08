Error when comparing expressions
The code
```
if a%5 == 0:
    ...
```
fails with pyccel because we search for the `dtype` property that does not belong to sympy objects:
```
    def [HIDDEN](self, expr):
        lhs = self._print(expr.lhs)
        rhs = self._print(expr.rhs)
        a = expr.args[0]
        b = expr.args[1]
>       [HIDDEN]
E           AttributeError: 'Mod' object has no attribute 'dtype'

pyccel/codegen/printing/fcode.py:1207: AttributeError
```
This bug can be fixed easily, [HIDDEN], but we should add some unit tests to verify this.

### Additional contract requirements

- Comparisons involving modulo expressions, such as `a%5 == 0`, must compile and evaluate without raising an `AttributeError` when a SymPy operand does not expose a `dtype` attribute. The compiled comparison must produce the same result as the corresponding Python comparison.
