[fuzz result] `![^x]` footnote reference eats the `!`
Consider this markdown:

```markdown
![^1]

[^1]: foo
```

Naturally, it should render as ![^1]. The `!` should show up, but it doesn't in pulldown-cmark.

[^1]: foo

<details>

Events from pulldown-cmark:

```rust
"![^+\\&~p+]\n[^+\\&~p+]:\n" -> [
  Start(Paragraph)
    FootnoteReference(Boxed("1"))
    Start(FootnoteDefinition(Boxed("1")))
    End(FootnoteDefinition)
  End(Paragraph)
]
```

Events from pandoc:

```rust
"![^+\\&~p+]\n[^+\\&~p+]:\n" -> [
  Start(Paragraph)
    Text(Boxed("!"))
    FootnoteReference(Boxed("1"))
    Start(FootnoteDefinition(Boxed("1")))
    End(FootnoteDefinition)
  End(Paragraph)
]
```

</details>
