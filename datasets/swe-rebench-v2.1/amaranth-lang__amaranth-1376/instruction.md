Zero-length submodule name breaks things
The following design:

```
from amaranth import *
from amaranth.back import verilog

class Bar(Elaboratable):
    def elaborate(self, platform):
        m = Module()
        m.d.sync += Signal().eq(1)
        return m

class Foo(Elaboratable):
    def elaborate(self, platform):
        m = Module()
        m.submodules[""] = Bar()
        return m

print(verilog.convert(Foo(), ports=[]))
```

gives the following exception:
```
Traceback (most recent call last):
  File "~/test.py", line 16, in <module>
    print(verilog.convert(Foo(), ports=[]))
  File "~/venv/lib/python3.10/site-packages/amaranth/back/verilog.py", line 61, in convert
    verilog_text, name_map = convert_fragment(fragment, ports, name, emit_src=emit_src, strip_internal_attrs=strip_internal_attrs, **kwargs)
  File "~/venv/lib/python3.10/site-packages/amaranth/back/verilog.py", line 39, in convert_fragment
    rtlil_text, name_map = rtlil.convert_fragment(*args, **kwargs)
  File "~/venv/lib/python3.10/site-packages/amaranth/back/rtlil.py", line 1029, in convert_fragment
    empty_checker=empty_checker).emit()
  File "~/venv/lib/python3.10/site-packages/amaranth/back/rtlil.py", line 308, in emit
    self.emit_submodules()
  File "~/venv/lib/python3.10/site-packages/amaranth/back/rtlil.py", line 516, in emit_submodules
    self.builder.cell(f"\\{dotted_name}", submodule.name[-1], ports={
  File "~/venv/lib/python3.10/site-packages/amaranth/back/rtlil.py", line 166, in cell
    name = self._make_name(name, local=False)
  File "~/venv/lib/python3.10/site-packages/amaranth/back/rtlil.py", line 67, in _make_name
    elif not local and name[0] not in "\\$":
IndexError: string index out of range
```

I suggest that `m.submodules[""] = ...` have the same behavior as `m.submodules += ...`. While it would be silly to directly write the former, it might arise from programmatic name generation, and should either work properly or immediately throw an error.
