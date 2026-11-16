get_var_name reports wrong name on Python 3.11
```python
class Test(Elaboratable):

    def __init__(self):
        self.i = Signal(4)

    def elaborate(self, platform):
        m = Module()

        a = Signal()
        print(a.name)

        b = Cat(self.i[i] & a for i in range(4))
        c = Signal(4)
        m.d.sync += c.eq(b)

        return m
```
Expected output is "a", but on Python 3.11, it prints "self". This happens when both self and the variable are cell vars (e.g., when they are used in a generator expression).

```python
            name_index = int(code.co_code[index + 1])
            if sys.version_info >= (3, 11):
                name_index -= code.co_nlocals
            return code.co_cellvars[name_index]
```
The line `name_index -= code.co_nlocals` assumes that `code.co_cellvars` does not contains any local variable but this is not the case if self is also a cell var. [HIDDEN]

### Additional contract requirements

- On Python 3.11 and later, when a local variable is also a cell variable, infer its actual name. In the reported case, the signal name must be `a`, not `self`.
