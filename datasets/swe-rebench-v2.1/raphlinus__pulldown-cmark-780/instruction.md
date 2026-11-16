[fuzz result] link definition destinations are being parsed with higher priority than setext headers
Consider this:

```markdown
[third try]:
-
```

[third try]:
-

pulldown-cmark thinks it's a link definition, but commonmark.js, commonmark-hs, and GitHub all think it's an H2

<details>

```rust
"[~]:\n-\n" -> [
]
```

Events from pandoc:

```rust
"[~]:\n-\n" -> [
  Start(Heading { level: H2, id: None, classes: [], attrs: [] })
    Text(Boxed("[~]:"))
  End(Heading(H2))
]
```

Events from commonmark.js:

```rust
"[~]:\n-\n" -> [
  Start(Heading { level: H2, id: None, classes: [], attrs: [] })
    Text(Boxed("[~]:"))
  End(Heading(H2))
]
```

</details>
