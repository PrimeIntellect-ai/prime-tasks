TypeError when formatting floating point literal
Formatting https://github.com/simeonschaub/FredholmDeterminants.jl/blob/0bf41942e3206252fa6a95fdc4f7207b38e601b9/test/runtests.jl fails with the following error:

```
ERROR: failed to format input from test/runtests.jl: TypeError: in typeassert, expected RegexMatch, got a value of type Nothing
Stacktrace:
 [1] format_float_literals(ctx::Runic.Context, node::Runic.Node)
   @ Runic ~/.julia/packages/Runic/uu8ya/src/runestone.jl:101
 [2] format_node!(ctx::Runic.Context, node::Runic.Node)
   @ Runic ~/.julia/packages/Runic/uu8ya/src/Runic.jl:543
 [3] format_node_with_kids!(ctx::Runic.Context, node::Runic.Node)
   @ Runic ~/.julia/packages/Runic/uu8ya/src/Runic.jl:458
 [4] format_node!(ctx::Runic.Context, node::Runic.Node)
   @ Runic ~/.julia/packages/Runic/uu8ya/src/Runic.jl:570
 [5] format_node_with_kids!(ctx::Runic.Context, node::Runic.Node)
   @ Runic ~/.julia/packages/Runic/uu8ya/src/Runic.jl:458
```

### Additional contract requirements

- When formatting floating-point literals, normalize the Unicode minus sign `−` (U+2212) to ASCII `-` (U+002D), both for a leading sign and an exponent sign. For example, `format_string("\u22121.0")` must return `"-1.0"`, `format_string("1.0e\u22121")` must return `"1.0e-1"`, and `format_string("\u22121.0e\u22121")` must return `"-1.0e-1"`.
