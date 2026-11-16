Format(data.Struct) gives YosysError
Running
```python
#!/usr/bin/env python3

from amaranth import Print, Module, Format, Signal
from amaranth.lib import data
from amaranth.back.verilog import convert

class A(data.Struct):
    x: 8
    b: 8

m = Module()

a = Signal(A)
m.d.sync += Print(Format("{}", a))

print(convert(m, ports=(a.as_value(),)))
```
yields
```
Traceback (most recent call last):
  File "/tmp/test.py", line 16, in <module>
    print(convert(m, ports=(a.as_value(),)))
  File "/data/projects/amaranth/amaranth/back/verilog.py", line 61, in convert
    verilog_text, name_map = convert_fragment(fragment, ports, name, emit_src=emit_src, strip_internal_attrs=strip_internal_attrs, **kwargs)
  File "/data/projects/amaranth/amaranth/back/verilog.py", line 40, in convert_fragment
    return _convert_rtlil_text(rtlil_text, strip_internal_attrs=strip_internal_attrs), name_map
  File "/data/projects/amaranth/amaranth/back/verilog.py", line 31, in _convert_rtlil_text
    return yosys.run(["-q", "-"], "\n".join(script),
  File "/data/projects/amaranth/amaranth/_toolchain/yosys.py", line 177, in run
    return cls._process_result(popen.returncode, stdout, stderr, ignore_warnings, src_loc_at)
  File "/data/projects/amaranth/amaranth/_toolchain/yosys.py", line 99, in _process_result
    raise YosysError(stderr.strip())
amaranth._toolchain.yosys.YosysError: ERROR: Assert `false && "Unexpected character in format substitution"' failed in kernel/fmt.cc:66.
```
When looking at the generated rtlil:
```
attribute \generator "Amaranth"
attribute \src "/tmp/test.py:11"
attribute \top 1
module \top

  attribute \src "/tmp/test.py:13"
  wire width 16 input 0  \a

  attribute \src "/data/projects/amaranth/amaranth/hdl/_ir.py:215"
  wire width 1 input 1  \clk

  attribute \src "/data/projects/amaranth/amaranth/hdl/_ir.py:215"
  wire width 1 input 2  \rst

  wire width 1 $1

  attribute \src "/tmp/test.py:13"
  wire width 8 \a.x

  attribute \src "/tmp/test.py:13"
  wire width 8 \a.b

  attribute \src "/tmp/test.py:14"
  process $2
    assign $1 [0] 1'0
    assign $1 [0] 1'1
  end

  attribute \src "/tmp/test.py:14"
  cell $print $3
    parameter \FORMAT "{{x={8:> du}, b={8:> du}}}\n"
    parameter \ARGS_WIDTH 16
    parameter signed \PRIORITY 32'11111111111111111111111111111110
    parameter \TRG_ENABLE 1
    parameter \TRG_WIDTH 1
    parameter \TRG_POLARITY 1
    connect \EN $1 [0]
    connect \ARGS \a [15:0]
    connect \TRG \clk [0]
  end

connect \a.x \a [7:0]
connect \a.b \a [15:8]

end
```
I guess the `{}` that enclose the struct are the problem, it looks like they need to be esacped.

### Additional contract requirements

Literal `{` and `}` characters in a `Print`/`Format` string must be escaped as `{{` and `}}` in the RTLIL `FORMAT` parameter. This includes the braces that `Format` emits when formatting a `data.Struct`: for a two-field struct `A` with fields `x: 8` and `b: 8`, `Print(Format("{}", a))` must produce `parameter \FORMAT "{{x={8:> du}, b={8:> du}}}\n"`.
