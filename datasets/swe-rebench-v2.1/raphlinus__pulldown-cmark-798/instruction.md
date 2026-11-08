[fuzz result] tight, nested lists can wrap block structures within emphasis
```console
$ cargo run
    Finished dev [unoptimized + debuginfo] target(s) in 0.02s
     Running `target/debug/pulldown-cmark`
- *foo
  - -
  baz*
^D
<ul>
<li><em>foo
<ul>
<li>
<ul>
<li></li>
</ul>
</li>
</ul>
baz</em></li>
</ul>
```

That's not valid HTML. The block elements need to be siblings with the inlines, and that can only happen in a tight list.

<details>

Events from pulldown-cmark:

```rust
"- *--\n  *  *\n  -*\n" -> [
  Start(List(None))
    Start(Item)
      Start(Emphasis)
        Text(Borrowed("--"))
        Start(List(None))
          Start(Item)
            Start(List(None))
              Start(Item)
              End(Item)
            End(List(false))
          End(Item)
        End(List(false))
        Text(Borrowed("-"))
      End(Emphasis)
    End(Item)
  End(List(false))
]
```

Events from pandoc:

```rust
"- *--\n  *  *\n  -*\n" -> [
  Start(List(None))
    Start(Item)
      Text(Boxed("*--"))
      Start(List(None))
        Start(Item)
          Start(List(None))
            Start(Item)
            End(Item)
          End(List(false))
        End(Item)
      End(List(false))
      Text(Boxed("-*"))
    End(Item)
  End(List(false))
]
```

Events from commonmark.js:

```rust
"- *--\n  *  *\n  -*\n" -> [
  Start(List(None))
    Start(Item)
      Text(Boxed("*--"))
      Start(List(None))
        Start(Item)
          Start(List(None))
            Start(Item)
            End(Item)
          End(List(false))
        End(Item)
      End(List(false))
      Text(Boxed("-*"))
    End(Item)
  End(List(false))
]
```

</details>

### Additional contract requirements

When inline formatting spans a nested block boundary in a tight list item, render the inline content and block structure as siblings; the block structure must not be nested inside the inline element.
