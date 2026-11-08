spurious warning for `Switch` over 0-width value
```
m = Module()
sw = Signal(0)
output = Signal()
with m.Switch(sw):
    with m.Case(0):
        m.d.comb += output.eq(1)
```

results in:

`SyntaxWarning: Case pattern '0' (1'0) is wider than switch value (which has width 0); comparison will never be true`
