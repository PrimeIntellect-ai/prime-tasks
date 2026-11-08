Interpolation in multiline strings doesn't work as expected
**Describe the bug**
In some situation, an interpolation sequence `#{exp}` inside a multi-line string is not interpreted as it should be.

**To Reproduce**
```
nickel> let x = "1" in m#""#{x}""#m
""#{1}""

nickel>
```

**Expected behavior**
`#{x}` should be properly interpolated as `1`

```
nickel> let x = "1" in m#""#{x}""#m
""1""

nickel>
```

**Additional context**
This seems to happen in particular when a double quote `"` precedes the interpolation sequence `#{`. I suspect it is consumed by the lexer as a potential closing delimiter `"#m`, taking precedence over `#{`.
