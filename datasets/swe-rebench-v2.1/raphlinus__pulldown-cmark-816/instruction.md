[fuzz result] lists should be more eager to interrupt tables
Things that look like lists, such as numbers starting at points other than 1 and lone asterisks on a line, should be able to interrupt tables even though they can't interrupt paragraphs. This, for example:

```markdown
moo | moo
----|----
moo | moo
13. Okay
```

It looks like this in GitHub:

> moo | moo
> ----|----
> moo | moo
> 13. Okay

<details>

Events from pulldown-cmark:

```rust
"|-\n|-\n*\n" -> [
  Start(Table([None]))
    Start(TableHead)
      Start(TableCell)
        Text(Borrowed("-"))
      End(TableCell)
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
"|-\n|-\n*\n" -> [
  Start(Table([None]))
    Start(TableHead)
      Start(TableCell)
        Text(Boxed("-"))
      End(TableCell)
    End(TableHead)
  End(Table)
  Start(List(None))
    Start(Item)
    End(Item)
  End(List(false))
]
```

</details>
