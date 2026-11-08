Add support for pandas eval
Hello, I'm running into an issue with using `pint_pandas` with pandas' `eval` function:

```python
import pandas as pd
import pint_pandas

df = pd.DataFrame({'a': pd.Series([1., 2., 3.], dtype='pint[meter]'), 'b': pd.Series([4., 5., 6.], dtype='pint[second]')})
# this works as expected
print(df['a'] / df['b'])
"""
0    0.25
1     0.4
2     0.5
dtype: pint[meter / second]
"""

# this is not working
print(df.eval('a / b'))
"""
TypeError: Cannot interpret 'pint[meter]' as a data type
"""
```

The problem arises when pandas tries to check if the columns are numeric by calling [this function](https://github.com/pandas-dev/pandas/blob/v1.5.0/pandas/core/computation/ops.py#L513). This is in turn passed to `np.dtype(dtype)`, which results in the below type error.

It's important for my application to use pandas eval, and the above is just a toy example.

Full stack trace:
```
Traceback (most recent call last):
  File "scratch_8.py", line 8, in <module>
    print(df.eval('a / b'))
  File "pandas/core/frame.py", line 4240, in eval
    return _eval(expr, inplace=inplace, **kwargs)
  File "pandas/core/computation/eval.py", line 350, in eval
    parsed_expr = Expr(expr, engine=engine, parser=parser, env=env)
  File "pandas/core/computation/expr.py", line 811, in __init__
    self.terms = self.parse()
  File "pandas/core/computation/expr.py", line 830, in parse
    return self._visitor.visit(self.expr)
  File "pandas/core/computation/expr.py", line 415, in visit
    return visitor(node, **kwargs)
  File "pandas/core/computation/expr.py", line 421, in visit_Module
    return self.visit(expr, **kwargs)
  File "pandas/core/computation/expr.py", line 415, in visit
    return visitor(node, **kwargs)
  File "pandas/core/computation/expr.py", line 424, in visit_Expr
    return self.visit(node.value, **kwargs)
  File "pandas/core/computation/expr.py", line 415, in visit
    return visitor(node, **kwargs)
  File "pandas/core/computation/expr.py", line 538, in visit_BinOp
    return self._maybe_evaluate_binop(op, op_class, left, right)
  File "pandas/core/computation/expr.py", line 505, in _maybe_evaluate_binop
    res = op(lhs, rhs)
  File "pandas/core/computation/expr.py", line 541, in <lambda>
    return lambda lhs, rhs: Div(lhs, rhs)
  File "pandas/core/computation/ops.py", line 536, in __init__
    if not isnumeric(lhs.return_type) or not isnumeric(rhs.return_type):
  File "pandas/core/computation/ops.py", line 520, in isnumeric
    return issubclass(np.dtype(dtype).type, np.number)
TypeError: Cannot interpret 'pint[meter]' as a data type
```
