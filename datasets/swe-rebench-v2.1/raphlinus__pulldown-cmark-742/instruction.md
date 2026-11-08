[fuzz result] incorrect run length matching in emphasis
Consider this examples, specifically the parts that are underlined with `-`s

```
**a.*.**a*.**.
 -          -
```

The [dingus](https://spec.commonmark.org/dingus/?text=**a.*.**a*.**.%0A%0A*a.*.**a*.**.) and pandoc both match the underlines delimiters together, but pulldown-cmark isn't.

[HIDDEN]

### Additional contract requirements

- Match compatible emphasis delimiter runs according to CommonMark run-length semantics. Prior matching decisions must not cause a later compatible run to be skipped; in the reported input, the underlined delimiters should match together.
