[fuzz result] quoted text is either just text, or a link title, but not both
Consider this markdown:

```markdown
[foo]: https://example.com
'[foo]'bar
```

The quoted text '[foo]' should either be treated as a paragraph, or as a title attribute. The reference implementation thinks just text, not a title. But pulldown-cmark treats it as *both*, generating `<p>'<a href="https://example.com" title="[foo]">foo</a>'bar</p>`.

<details>

Events from pulldown-cmark:

```rust
"[R>]:[\n'\n[R>]'6\n" -> [
  Start(Paragraph)
    Text(Boxed("'"))
    SoftBreak
    Start(Link { link_type: Inline, dest_url: Borrowed("["), title: Borrowed("\n[R>]"), id: Borrowed("") })
      Text(Borrowed("R>"))
    End(Link)
    Text(Borrowed("'6"))
  End(Paragraph)
]
```

Events from pandoc:

```rust
"[R>]:[\n'\n[R>]'6\n" -> [
  Start(Paragraph)
    Text(Boxed("'"))
    SoftBreak
    Start(Link { link_type: Inline, dest_url: Inlined(InlineStr { inner: [91, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 1 }), title: Inlined(InlineStr { inner: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 0 }), id: Borrowed("") })
      Text(Boxed("R>"))
    End(Link)
    Text(Boxed("'6"))
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"[R>]:[\n'\n[R>]'6\n" -> [
  Start(Paragraph)
    Text(Boxed("'"))
    SoftBreak
    Start(Link { link_type: Inline, dest_url: Inlined(InlineStr { inner: [91, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 1 }), title: Inlined(InlineStr { inner: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], len: 0 }), id: Borrowed("") })
      Text(Boxed("R>"))
    End(Link)
    Text(Boxed("'6"))
  End(Paragraph)
]
```

</details>

### Additional contract requirements

- For this Markdown input:

```markdown
- [foo]: https://example.com
'[foo]'
[foo]
```

The rendered HTML must be:

```html
<ul>
<li>
<a href="https://example.com" title="[foo]">foo</a>
</li>
</ul>
```
