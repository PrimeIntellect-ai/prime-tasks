Generated SystemVerilog includes index access on 1-bit signals
### Describe the bug

If a signal is defined as 1 bit in SystemVerilog:
```verilog
logic x;
```
Then you should not access the 0'th bit of it like this:
```verilog
x[0]
```
However, ROHD can generate this.

### To Reproduce

Access the 0'th bit of a `Logic` and generate SystemVerilog for it.

### Expected behavior

When a signal is 1 bit, treat a 0-index into it as a nop and generate accesses as just the raw signal.  It's probably even better to just short-circuit this and return the signal itself immediately to save the extra work of a nop module.

### Actual behavior

Generated verilog has `x[0]`-like behavior for 1-bit signals

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

This bug likely applies to both `slice`/`BusSubset` via constant indexing and `IndexGate`.

### Additional contract requirements

- Accessing bit 0 of a one-bit `Logic` preserves its value, including an unknown value.
- Constant bit-0 access or a `0:0` slice of a one-bit signal generates SystemVerilog that refers to the raw signal without a bit-select, including when the selection is represented by `BusSubset`.
- When a one-bit original is accessed through `IndexGate`, generated SystemVerilog refers to the raw original signal without a bit-select.
