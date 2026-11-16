Custom converter functions are not recognized for heading tags
When creating custom converters with MarkdownConverter for specific tags, all converters for `h1`-`h6` headings are ignored, and headings are processed according to the standard converter options.

```html
<h1>This is a heading</h1>
<p>This is a paragraph</p>
```

```python
class FixMarkup(MarkdownConverter):
    def convert_h1(self, el, text, parent_tags):
        return 'Heading override'

def md(html, **options):
    return FixMarkup(**options).convert(html)

markdown = md(html, heading_style='ATX')
```

**Expected output:**

```markdown
Heading override

This is a paragraph
```

**Actual output:**

```markdown
# This is a heading

This is a paragraph
```
