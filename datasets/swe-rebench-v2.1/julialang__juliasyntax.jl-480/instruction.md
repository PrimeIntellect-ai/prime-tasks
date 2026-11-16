Fix premature lowering of `K"core_@cmd"` etc
There are four macrocalls to special `Kind`s which are arguably premature lowering.

```
K"core_@cmd"
K"core_@int128_str"
K"core_@uint128_str"
K"core_@big_str"
```

In the same way that we removed `K"core_@doc` previously (see #217), these should have their own kinds instead:

```
K"cmdstring" # ??
K"Int128"
K"UInt128"
K"BigInt"
```

For `K"core_@cmd"` there might be some thought required: it could be either
* A single `K"CmdString"`, with the delimiters as separate trivia tokens in the parent?
* A `K"cmdstring"` container - in analogy to `K"string"` - with a `K"String"` or `K"CmdString"` chunk inside?

### Additional contract requirements

- Bare backtick command literals, including triple-backtick literals, must not produce a macrocall to `Core.@cmd` in the syntax tree.
