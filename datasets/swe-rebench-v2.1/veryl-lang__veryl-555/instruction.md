Change from `assign` to `always_comb` in emitted SystemVerilog code
`assign` statement of SystemVerilog have a restriction about sensitivity list.
If there is function call in the right-hand of `assign` statement like below, the signals referenced in the function are not listed in sensitivity list. This behavior may be unexpected.
On the other hand, `always_comb` lists all signals to sensitivity list.

```systemverilog
assign      a = func(); // NG
always_comb a = func(); // OK
```

So the emitted code of Veryl should use `always_comb` instead of `assign`.

### Additional contract requirements

- Each assignment that is currently emitted as `assign <target> = <expression>;` must be emitted as `always_comb <target> = <expression>;` on the same line. Only the leading keyword changes: the target, the expression, and the spacing around them (including any column alignment the emitter already produces for consecutive assignments) stay exactly as they are today.
- This applies to every place where the generated SystemVerilog currently contains an `assign` statement for a Veryl assignment, including assignments whose right-hand side is a function call, a system function call, or a cast.
