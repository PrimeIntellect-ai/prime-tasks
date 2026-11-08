[fuzz result] "table head" with trailing characters getting counted as a header
Something that looks like a table header, but has trailing text, shouldn't count as a table. It plainly contradicts what the spec says here (and disagrees with Pandoc Markdown, Pandoc GFM, actual GFM, and everything else I think to try).

```markdown
|
-|- *
```

<details>

Events from pulldown-cmark:

```rust
"\n |\n-|- *\n" -> [
  Start(Table([]))
    Start(TableHead)
    End(TableHead)
    Start(TableRow)
      Start(TableCell)
        Text(Borrowed("*"))
      End(TableCell)
    End(TableRow)
  End(Table)
]
```

Events from pandoc:

```rust
"\n |\n-|- *\n" -> [
  Start(Paragraph)
    Text(Boxed("|"))
    SoftBreak
    Text(Boxed("-|- *"))
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"\n |\n-|- *\n" -> [
  Start(Paragraph)
    Text(Boxed("|"))
    SoftBreak
    Text(Boxed("-|- *"))
  End(Paragraph)
]
```

</details>
