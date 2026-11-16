test_extract_operands never fails
py.test warns me about this:

> babel/tests/test_plural.py:257: SyntaxWarning: assertion is always true, perhaps remove parentheses?

``` python
    assert (plural.extract_operands(source) ==
            Decimal(n), i, v, w, f, t)
```

Just removing the parens (and rewrapping the statement) makes the test fail though, so it needs some work.
