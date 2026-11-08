can't call pure internal function from pure function
### Version Information

* vyper Version (output of `vyper --version`): 42a372e95cb50ead4c9906cd0c6c50d5de881f8b
* Python Version (output of `python --version`): v3.8.10

### What's your issue about?
repro:
```vyper
@pure
@internal
def foo():
    pass

@pure
@internal
def bar():
    self.foo()
```
