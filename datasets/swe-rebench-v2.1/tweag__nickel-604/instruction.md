Cannot put string interpolation inside quotes in a multiline string if using multiple #
**Describe the bug**
When creating a multiline string with multiple `#`, if I want to put the result of an interpolation between quotes, I got this parsing error:
```
> let s = "Hello" in m##""##{s}" World"##m

error: Unexpected token
  ┌─ repl-input-1:1:34
  │
1 │let s = "Hello" in m##""##{s}" World"##m
  │                       ^^^
```

**Expected behavior**
I expected this to generate `""Hello" World"`, since this other example with only one `#` works:
```
> let s = "Hello" in m#""#{s}" World"#m
""Hello" World"
```

Also, this example with an extra space works too:
```
> let s = "Hello" in m##"" ##{s}" World"##m
"" Hello" World"
```

**Environment**
 - rust version: 1.58.1
 - Version of the code: 9f618e6ca6d6d7cee6826dbf44d462f4ceb28e8a

### Additional contract requirements

The fix must generalize to the following multiline string expressions. With `s` bound to `"Hello"`:

- `m##""###{s}" World"##m` must evaluate to `"#Hello" World`.
- `m##""##s"##m` must evaluate to `"##s`.
