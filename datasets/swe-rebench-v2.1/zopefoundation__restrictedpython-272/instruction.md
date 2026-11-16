Unable to compile single expressions
## PROBLEM REPORT

Attempted a simple `compile_restricted` using `single`.

```python
x = 50
code = compile_restricted('x + 25', '<string>', 'single')
```

### What I did:

Attempted a simple comparison with `compile()`. Also, compared it with `exec`.

```python
x = 50
code = compile('x + 25', '<string>', 'single')
exec(code)

assert x == 75
```

### What I expect to happen:

Should be able to compile a single expression and execute with the associated side-effects similar to `compile()`.

### What actually happened:

```
SyntaxError: ('Line None: Interactive statements are not allowed.',)
```

### What version of Python and Zope/Addons I am using:
Python 3.11.8
RestrictedPython 7.0

### Additional contract requirements

Restricted compilation in `single` mode must accept an expression and execute it with Python interactive-mode semantics. An expression such as `x + 25` evaluates that expression; it does not reassign `x`. Any side effects performed by the expression must occur when its code runs. The restricted single-mode entry points must continue to enforce RestrictedPython's safety restrictions.
