HR preceeded by ***word*** doesn't render as HR
Input:

```
***test***
***
```

Output (second line will be rendered as a literal `***`):

```html
<p><strong><em>test</em></strong>
***</p>
```

Expected output according to Markdown.pl:

```html
<p><strong><em>test</em></strong>
</p>
<hr />
```

The same problem occurs with `---` and `___` as HR.

[HIDDEN]

```diff
497c497
<     RE = r'^[ ]{0,3}((-+[ ]{0,2}){3,}|(_+[ ]{0,2}){3,}|(\*+[ ]{0,2}){3,})[ ]*'
---
[HIDDEN]
```

### Additional contract requirements

- When a paragraph containing strong-and-emphasis text is followed by a horizontal-rule line, the line must render as an `<hr />`, not as literal text within the paragraph. This applies to `***`, `---`, and `___` horizontal-rule lines.
