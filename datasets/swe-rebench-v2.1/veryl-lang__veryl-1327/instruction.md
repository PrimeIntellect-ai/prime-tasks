Type cast at port connection is ignored
Type cast at port connection is ignored, and "sv_with_implicit_reset" occurs in the following code

```systemverilog
inst u: $sv::SvModule (
    i_rst_n: i_rst as reset_async_low,
);
```

### Additional contract requirements

An explicit reset-type cast on an instance port connection must be respected during analysis. In particular, connecting a `reset` signal with an explicit `reset_async_low` cast must not produce an implicit-reset diagnostic for that connection.
