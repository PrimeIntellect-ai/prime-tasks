`RecursionError` in `InterestingOrigin.from_exception` with recursive `__context__`
```python
def test_recursive_exception():
    @given(st.data())
    def test_function(data):
        try:
            raise ExceptionGroup("", [ValueError()])
        except ExceptionGroup as eg:
            raise eg.exceptions[0] from None
    test_function()
```
causes an infinite recursion in `InterestingOrigin.from_exception`
https://github.com/HypothesisWorks/hypothesis/blob/879225d8836c657fe970ceb1a95df072e06352d4/hypothesis-python/src/hypothesis/internal/escalation.py#L110-L127

Due to `exception.__context__.exceptions[0] is exception`.
You can also do it without exceptiongroups, but idk if this would ever be encountered in the wild:
```python
def test_recursive_exception2():
    @given(st.data())
    def test_function(data):
        k = ValueError()
        k.__context__ = k
        raise k
    test_function()
```


Encountered during development of #4110
