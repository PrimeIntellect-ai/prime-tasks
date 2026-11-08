arrays nested in complex types can be modified during iteration
### Version Information

* vyper Version (output of `vyper --version`): v0.3.3
* Python Version (output of `python --version`): v3.8.10

### What's your issue about?
the following code compiles, when it shouldn't
```vyper
struct Foo:
    foo: uint256[4] # DynArray[uint256, 100]

my_array2: Foo

@internal
def doStuff(i: uint256) -> uint256:
    self.my_array2.foo[i] = i
    return i

@internal
def _helper():
    i: uint256 = 0
    for item in self.my_array2.foo:
        self.doStuff(i)
        i += 1
```

### How can it be fixed?
related to https://github.com/vyperlang/vyper/issues/2865

probably, this analysis needs to get more sophisticated. right now it looks for AST similarities, but it should probably be based on tagging nodes with modification analysis instead. https://github.com/vyperlang/vyper/blob/1b0521b361b90b9dc356707886730dfacd6631ba/vyper/semantics/validation/local.py#L91-L106
