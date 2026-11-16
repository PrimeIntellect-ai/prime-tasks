[fuzz result] misparse on single-line header with backslash
Events from pulldown-cmark:

```rust
"# \\\n\n\n" -> [
  Start(Heading { level: H1, id: None, classes: [], attrs: [] })
  End(Heading(H1))
]
```

Events from pandoc:

```rust
"# \\\n\n\n" -> [
  Start(Heading { level: H1, id: None, classes: [], attrs: [] })
    Text(Boxed("\\"))
  End(Heading(H1))
]
```

Events from commonmark.js:

```rust
"# \\\n\n\n" -> [
  Start(Heading { level: H1, id: None, classes: [], attrs: [] })
    Text(Boxed("\\"))
  End(Heading(H1))
]
```
