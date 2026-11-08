[fuzz result] footnote definition not parsed when there's <4 spaces indentation
`foo` and `bar` should both be footnote definitions, but `foo` is getting parsed as a link (and the reference made later isn't working right):

```markdown
 [^foo]: x

[^bar]: x

Test [^foo] / [^bar]
```

Result:

```html
<div class="footnote-definition" id="bar"><sup class="footnote-definition-label">1</sup>
<p>x</p>
</div>
<p>Test [^foo] / <sup class="footnote-reference"><a href="#bar">1</a></sup></p>
```

<details>

Events from pulldown-cmark:

```rust
" [^|]:\n" -> [
  Start(Paragraph)
    Text(Boxed("[^|]:"))
  End(Paragraph)
]
```

Events from pandoc:

```rust
" [^|]:\n" -> [
]
```
