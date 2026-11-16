[fuzz result] tight lists can wrap atx header within emphasis
Similar to https://github.com/raphlinus/pulldown-cmark/issues/797

```console
$ cargo run
    Finished dev [unoptimized + debuginfo] target(s) in 0.02s
     Running `target/debug/pulldown-cmark`
- _t
  # test
  t_
<ul>
<li><em>t
<h1>test</h1>
t</em></li>
</ul>

```

<details>

Events from pulldown-cmark:

```rust
"+ _t\n  #\n  *_\n" -> [
  Start(List(None))
    Start(Item)
      Start(Emphasis)
        Text(Borrowed("t"))
        Start(Heading { level: H1, id: None, classes: [], attrs: [] })
        End(Heading(H1))
        Text(Borrowed("*"))
      End(Emphasis)
    End(Item)
  End(List(false))
]
```

Events from pandoc:

```rust
"+ _t\n  #\n  *_\n" -> [
  Start(List(None))
    Start(Item)
      Text(Boxed("_t"))
      Start(Heading { level: H1, id: None, classes: [], attrs: [] })
      End(Heading(H1))
      Text(Boxed("*_"))
    End(Item)
  End(List(false))
]
```

Events from commonmark.js:

```rust
"+ _t\n  #\n  *_\n" -> [
  Start(List(None))
    Start(Item)
      Text(Boxed("_t"))
      Start(Heading { level: H1, id: None, classes: [], attrs: [] })
      End(Heading(H1))
      Text(Boxed("*_"))
    End(Item)
  End(List(false))
]
```

</details>
