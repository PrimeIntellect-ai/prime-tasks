Incorrect HTML output for code span containing `</>`
In markdown==3.8, a code span containing the string "\`</>\`" is incorrectly rendered. Instead of producing the expected HTML output with the characters escaped, it strips the content entirely:

```pycon
>>> import markdown
>>> markdown.__version__
'3.8'

>>> markdown.markdown('`</>`')
'<p>``</p>'
```

**Expected result:**

```python
`'<p><code>&lt;/&gt;</code></p>'`
```

Other examples that work correctly:

```pycon
>>> markdown.markdown('`<`')
✅ '<p><code>&lt;</code></p>'
>>> markdown.markdown('`</`')
✅ '<p><code>&lt;/</code></p>'
>>> markdown.markdown('`</>`')
❌ '<p>``</p>'
>>> markdown.markdown('`/>`')
✅ '<p><code>/&gt;</code></p>'
>>> markdown.markdown('`>`')
✅ '<p><code>&gt;</code></p>'
```

This issue appears specific to the combination `</>`. Would appreciate any insight into whether this is a known bug, an edge case in the parser, or an intentional (though surprising) behavior. Thanks!
