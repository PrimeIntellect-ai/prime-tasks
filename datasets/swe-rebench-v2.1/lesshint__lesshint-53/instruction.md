False positive with "singleLinePerProperty"
`singleLineProperty` is returning a false positive for inline comments.

Valid CSS

```LESS
.foo {
  background-color: #000;
  color: #000; // black on black
}
```

Shouldn't error
```
test.less: line 3, col 5, singleLinePerProperty: Each property should be on it's own line.
```

Please add support for inline comments

### Additional contract requirements

A property on its own line remains valid when followed by an inline comment. A comment must not hide multiple property declarations that share a line; each such declaration must still be reported. A property that shares a line with its ruleset's opening or closing brace also violates the one-property-per-line rule.
