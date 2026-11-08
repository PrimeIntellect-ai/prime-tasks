Too much skipping after invalid token in `for` element name
### Issue Kind

Bad Diagnostic Produced

### Source Code

```swift
for var elem? in arr { }
```

### Description

This results diagnostics:
```
test.swift:1:13: error: expected 'in' and expression in 'for' statement
1 │ for var elem? in arr { }
  │             ├─ error: expected 'in' and expression in 'for' statement
  │             ╰─ error: unexpected code '? in arr' in 'for' statement
2 │
```
And in the parsed syntax tree `? in arr ` part is parsed as `CodeBlockItemSyntax.unexpectedBeforeLeftBrace`

### Additional contract requirements

- For `for var elem? in arr { }`, emit the diagnostic `unexpected code '?' in 'for' statement`.
- Keep the valid `in arr` portion available as the loop's `in` keyword and sequence expression; do not absorb it into unexpected code before the loop body.
