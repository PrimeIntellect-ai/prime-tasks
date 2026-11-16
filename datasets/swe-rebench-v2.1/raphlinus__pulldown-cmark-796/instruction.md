[fuzz result] blank line after blockquote with unclosed code block doesn't split
[The spec](https://spec.commonmark.org/0.30/#example-242):

> A blank line always separates block quotes:

Events from pulldown-cmark:

```rust
">~~~\n\n>\n" -> [
  Start(BlockQuote)
    Start(CodeBlock(Fenced(Borrowed(""))))
    End(CodeBlock)
  End(BlockQuote)
]
```

Events from pandoc:

```rust
">~~~\n\n>\n" -> [
  Start(BlockQuote)
    Start(CodeBlock(Fenced(Borrowed(""))))
    End(CodeBlock)
  End(BlockQuote)
  Start(BlockQuote)
  End(BlockQuote)
]
```

Events from commonmark.js:

```rust
">~~~\n\n>\n" -> [
  Start(BlockQuote)
    Start(CodeBlock(Fenced(Borrowed(""))))
    End(CodeBlock)
  End(BlockQuote)
  Start(BlockQuote)
  End(BlockQuote)
]
```
