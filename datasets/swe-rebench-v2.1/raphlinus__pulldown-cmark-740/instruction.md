[fuzz result]: Incorrect match nesting when an unmatched delimiter is flanked by other delimiters
Notice the very counterintuitive behavior where `_x_\n*{*{` recognizes the last two asterisks as delimiters, but if the `x` is turned into an asterisk, they stop being recognized.

Events from pulldown-cmark:

```rust
"_*_\n*{*{\n" -> [
  Start(Paragraph)
    Start(Emphasis)
      Text(Borrowed("*"))
    End(Emphasis)
    SoftBreak
    Text(Boxed("*{*{"))
  End(Paragraph)
]
```

Events from pandoc:

```rust
"_*_\n*{*{\n" -> [
  Start(Paragraph)
    Start(Emphasis)
      Text(Boxed("*"))
    End(Emphasis)
    SoftBreak
    Start(Emphasis)
      Text(Boxed("{"))
    End(Emphasis)
    Text(Boxed("{"))
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"_*_\n*{*{\n" -> [
  Start(Paragraph)
    Start(Emphasis)
      Text(Boxed("*"))
    End(Emphasis)
    SoftBreak
    Start(Emphasis)
      Text(Boxed("{"))
    End(Emphasis)
    Text(Boxed("{"))
  End(Paragraph)
]
```

AST from [pandoc](https://pandoc.org/try/?params=%7B%22text%22%3A%22_%2A_%5Cn%2A%7B%2A%7B%5Cn%22%2C%22to%22%3A%22json%22%2C%22from%22%3A%22commonmark%22%7D):

```text
Pandoc {
    meta: {},
    blocks: [
        Para(
            [
                Emph(
                    [
                        Str(
                            "*",
                        ),
                    ],
                ),
                SoftBreak,
                Emph(
                    [
                        Str(
                            "{",
                        ),
                    ],
                ),
                Str(
                    "{",
                ),
            ],
        ),
    ],
}
```
