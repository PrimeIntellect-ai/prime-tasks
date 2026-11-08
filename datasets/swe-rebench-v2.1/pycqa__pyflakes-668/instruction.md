Is an unused variable annotation able to be detected?
Given this sample file:

```python
def foo():
    a = 10
    b: str
    return 1


foo()
```

It correctly gives an error about the variable `a`: `test.py:2:5 local variable 'a' is assigned to but never used`

It would be nice if an error could be given about `b` as well since it is also never used. I'm not sure if this is a bug report or a feature request, but I just wasn't sure if this was possible.
