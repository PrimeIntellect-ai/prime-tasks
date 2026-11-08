[fuzz result] last line of link title is silently eaten
Here's a readable reduction:

```console
$ cargo run
   Compiling pulldown-cmark v0.9.2 (/home/michael/Development/pulldown-cmark)
    Finished dev [unoptimized + debuginfo] target(s) in 1.22s
     Running `target/debug/pulldown-cmark`
[mylink]

[mylink]: https://example.com
'
not part of the title'
<p><a href="https://example.com" title="
">mylink</a></p>
```

The phrase "not part of the title" should be part of the title, and it isn't.

<details>

```rust
"/ [^~]:'\nR\n+  [^~]:[\n'\n]^~]?'\n\n[\n" -> [
  Start(Paragraph)
    Text(Borrowed("/ "))
    Start(Link { link_type: Inline, dest_url: Borrowed("["), title: Inlined(InlineStr { inner: [10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 1 }), id: Borrowed("") })
      Text(Borrowed("^~"))
    End(Link)
    Text(Boxed(":'"))
    SoftBreak
    Text(Boxed("R"))
  End(Paragraph)
  Start(List(None))
    Start(Item)
    End(Item)
  End(List(false))
  Start(Paragraph)
    Text(Borrowed("["))
  End(Paragraph)
]
```

Events from pandoc:

```rust
"/ [^~]:'\nR\n+  [^~]:[\n'\n]^~]?'\n\n[\n" -> [
  Start(Paragraph)
    Text(Boxed("/ "))
    Start(Link { link_type: Inline, dest_url: Inlined(InlineStr { inner: [91, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 1 }), title: Inlined(InlineStr { inner: [10, 93, 94, 126, 93, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 6 }), id: Borrowed("") })
      Text(Boxed("^~"))
    End(Link)
    Text(Boxed(":'"))
    SoftBreak
    Text(Boxed("R"))
  End(Paragraph)
  Start(List(None))
    Start(Item)
    End(Item)
  End(List(false))
  Start(Paragraph)
    Text(Boxed("["))
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"/ [^~]:'\nR\n+  [^~]:[\n'\n]^~]?'\n\n[\n" -> [
  Start(Paragraph)
    Text(Boxed("/ "))
    Start(Link { link_type: Inline, dest_url: Inlined(InlineStr { inner: [91, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 1 }), title: Inlined(InlineStr { inner: [10, 93, 94, 126, 93, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 6 }), id: Borrowed("") })
      Text(Boxed("^~"))
    End(Link)
    Text(Boxed(":'"))
    SoftBreak
    Text(Boxed("R"))
  End(Paragraph)
  Start(List(None))
    Start(Item)
    End(Item)
  End(List(false))
  Start(Paragraph)
    Text(Boxed("["))
  End(Paragraph)
]
```

</details>
