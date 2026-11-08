`Options::ENABLE_DEFINITION_LIST` changes the parsing of lazy continuation lines
Given the following input:

```markdown
> text in blockquote
:lazy continuation line
```

Running `cargo run -- -e` returns these events:

```
0..44: Start(BlockQuote(None))
2..44: Start(Paragraph)
2..20: Text(Borrowed("text in blockquote"))
20..21: SoftBreak
21..43: Text(Borrowed(":not a definition list"))
2..44: End(Paragraph)
0..44: End(BlockQuote(None))
EOF
```

Running `cargo run -- -e --enable-definition-list ` changes how the lazy continuation line is parsed. My guess is the `:` at the start of the line makes the parser think it needs to close the preceding blockquote and paragraph.

```markdown
0..21: Start(BlockQuote(None))
2..21: Start(Paragraph)
2..20: Text(Borrowed("text in blockquote"))
2..21: End(Paragraph)
0..21: End(BlockQuote(None))
21..44: Start(Paragraph)
21..43: Text(Borrowed(":not a definition list"))
21..44: End(Paragraph)
EOF
```

### Additional contract requirements

The lazy-continuation behaviour described above must also hold when the
colon-prefixed line appears inside a nested definition-list or blockquote
context. The following inputs must render exactly as shown (after the
standard HTML normalisation that collapses line breaks between tags).

Input:

```markdown
apple
   : > computer company
     : red fruit

orange
   : > telecom company
   : orange fruit

chili's
   : > restaurant company
 : spicy fruit
```

Output:

```html
<dl>
<dt>apple</dt>
<dd><blockquote>
<p>computer company
: red fruit</p>
</blockquote>
</dd>
<dt>orange</dt>
<dd><blockquote>
<p>telecom company</p>
</blockquote>
</dd>
<dd>orange fruit</dd>
<dt>chili's</dt>
<dd><blockquote>
<p>restaurant company</p>
</blockquote>
</dd>
<dd>spicy fruit</dd>
</dl>
```

Input:

```markdown
> cherry
> : keyboard company
> pomegranate
: tart fruit
```

Output:

```html
<blockquote>
<dl>
<dt>cherry</dt>
<dd>keyboard company
pomegranate
: tart fruit</dd>
</dl>
</blockquote>
```
