HTML has higher priority than block quotes
Found with modified differential fuzzer (please mark as a fuzzing output): https://github.com/raphlinus/pulldown-cmark/pull/673

Events from pulldown-cmark:

```rust
"<G\n>\n" -> [
  Start(Paragraph)
    Html(Boxed("<G\n>"))
  End(Paragraph)
]
```

Events from pandoc:

```rust
"<G\n>\n" -> [
  Start(Paragraph)
    Text(Boxed("<G"))
  End(Paragraph)
  Start(BlockQuote)
  End(BlockQuote)
]
```

Events from commonmark.js:

```rust
"<G\n>\n" -> [
  Start(Paragraph)
    Text(Boxed("<G"))
  End(Paragraph)
  Start(BlockQuote)
  End(BlockQuote)
]
```

AST from [pandoc](https://pandoc.org/try/?params=%7B%22text%22%3A%22%3CG%5Cn%3E%5Cn%22%2C%22to%22%3A%22json%22%2C%22from%22%3A%22commonmark%22%7D):

```text
Pandoc {
    meta: {},
    blocks: [
        Para(
            [
                Str(
                    "<G",
                ),
            ],
        ),
        BlockQuote(
            [],
        ),
    ],
}
```

### Additional contract requirements

When a multiline raw HTML block such as `<div` continues on a line beginning with `>`, preserve that continuation as raw HTML rather than interpreting it as a block quote.
