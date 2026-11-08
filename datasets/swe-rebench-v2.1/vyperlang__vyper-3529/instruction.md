bug: references to public constants and immutables with self are missed by the typechecker
### Version Information

* vyper Version (output of `vyper --version`): https://github.com/vyperlang/vyper/commit/9e3b9a2b8ae55aa83b5450080f750be15f819de7
* OS: linux
* Python Version (output of `python --version`): 3.10.4

### What's your issue about?

[HIDDEN] The compiler later fails during the codegen.

Compiling the following contract will fail with `KeyError: 'a'`.
```
a:public(constant(uint256)) = 1

@external
def foo():
    b: uint256 = self.a
```

h/t @trocher

### How can it be fixed?

Fill this in if you know how to fix it.

### Additional contract requirements

- The typechecker must reject references written as `self.<name>` to public constants and immutables, rather than allowing them to fail later during code generation.
