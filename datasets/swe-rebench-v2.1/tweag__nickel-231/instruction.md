Wrong handling of `#` character in multiline strings
**Describe the bug**
A `#` or a sequence of `#` in a multiline string causes a parse error.

**To Reproduce**
 ```
% nickel <<< 'm#"Hel#lo"#m'
error: Unexpected token
  ┌─ <stdin>:1:7
  │
1│ m#"Hel#lo"#m
  │       ^
```

**Expected behavior**
The program evaluates without error:
```
% nickel <<< 'm#"Hel#lo"#m'
Done: Str("Hel#lo")
```
