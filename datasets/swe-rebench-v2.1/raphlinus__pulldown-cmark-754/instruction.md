[fuzz result] backslash escapes in link def prevent paragraph breaks
Consider this markdown:

```markdown
[x\

]: https://rust-lang.org
```

That's not a link definition, but pulldown-cmark thinks it is. The hard line break on line 1 is an inline element, and should not prevent the paragraph break from parsing.

<details>

Events from pulldown-cmark:

```rust
"[\\\n\n]:l\n" -> [
]
```

Events from pandoc:

```rust
"[\\\n\n]:l\n" -> [
  Start(Paragraph)
    Text(Boxed("[\\"))
  End(Paragraph)
  Start(Paragraph)
    Text(Boxed("]:l"))
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"[\\\n\n]:l\n" -> [
  Start(Paragraph)
    Text(Boxed("[\\"))
  End(Paragraph)
  Start(Paragraph)
    Text(Boxed("]:l"))
  End(Paragraph)
]
```

AST from [pandoc](https://pandoc.org/try/?params=%7B%22text%22%3A%22%5B%5C%5C%5Cn%5Cn%5D%3Al%5Cn%22%2C%22to%22%3A%22json%22%2C%22from%22%3A%22commonmark%22%7D):

```text
Pandoc {
    meta: {},
    blocks: [
        Para(
            [
                Str(
                    "[\\",
                ),
            ],
        ),
        Para(
            [
                Str(
                    "]:l",
                ),
            ],
        ),
    ],
}
```
