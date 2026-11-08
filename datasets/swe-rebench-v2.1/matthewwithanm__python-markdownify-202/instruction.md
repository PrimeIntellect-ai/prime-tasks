`<br/>` in inline contexts does not evaluate to a separating space
Currently, `<br/>` in inline contexts (such as headings and table cells) evaluates to an empty string instead of a separating space:

```python
from markdownify import MarkdownConverter

def md(html, **options):
    return MarkdownConverter(heading_style="ATX").convert(html)

print(repr(md('<h1>foo<br />bar</h1>')))
# '# foobar'
#    ^^^^^^

print(repr(md('<td>foo<br />bar</td>')))
# ' foobar |'
#   ^^^^^^
```

In inline contexts, `<br/>` should evaluate to a separating space.
