[fuzz result] footnote definitions in blockquotes do not match on first line
This markdown:

```markdown
> [^5]: * test
>
> test [^5]
```

On GitHub, it looks like this:

> [^5]: * test
>
> test [^5]

(the block quote appears at the end of the document, but it still parses)

pulldown-cmark isn't recognizing it, parsing it as text

<details>

```rust
">>  [^^]:>,* 8[\n" -> [
  Start(BlockQuote)
    Start(BlockQuote)
      Start(Paragraph)
        Text(Boxed("[^^]:>,* 8["))
      End(Paragraph)
    End(BlockQuote)
  End(BlockQuote)
]
```

Events from pandoc:

```rust
">>  [^^]:>,* 8[\n" -> [
  Start(BlockQuote)
    Start(BlockQuote)
    End(BlockQuote)
  End(BlockQuote)
]
```

Events from commonmark.js:

```rust
">>  [^^]:>,* 8[\n" -> [
  Start(BlockQuote)
    Start(BlockQuote)
      Start(Paragraph)
        Text(Boxed("[^^]:>,* 8["))
      End(Paragraph)
    End(BlockQuote)
  End(BlockQuote)
]
```

</details>

### Additional contract requirements

- For the Markdown input `> [^5]: * test\n>\n> test [^5]`, the HTML output must be exactly:

```html
<blockquote>
<div class="footnote-definition" id="5"><sup class="footnote-definition-label">1</sup>
<ul>
<li>test</li>
</ul>
</div>
<p>test <sup class="footnote-reference"><a href="#5">1</a></sup></p>
</blockquote>
```
