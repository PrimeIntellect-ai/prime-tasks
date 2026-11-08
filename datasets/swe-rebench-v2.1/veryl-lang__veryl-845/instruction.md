Variable prefix/suffix is not effective at some places
Prefix/suffix originated from build configurations like `reset_low_prefix` is not effective at some places like implicit port connection.

```systemverilog
module ModuleA (
    i_rst: input reset,
) {
    inst u: ModuleB (
         i_rst,
    );
}
```

will be

```systemverilog
module ModuleA (
    input logic i_rst_n
);
    ModuleB u (
        .i_rst_n(i_rst) // should be .i_rst_n(i_rst_n)
    );
endmodule
```
