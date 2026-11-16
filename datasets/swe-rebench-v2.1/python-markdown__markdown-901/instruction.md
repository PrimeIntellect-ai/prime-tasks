Heading names in toc_tokens contain stashed HTML placeholders
If a Markdown heading contains HTML, the corresponding entry in the `.toc_tokens` property ends up with HTML placeholders when returned to the user. The following example should illustrate the problem:

```
>>> import markdown
>>> md = markdown.Markdown(extensions=['toc'])
>>> md.convert('# <code>Heading</code>\n')
'<h1 id="heading"><code>Heading</code></h1>'
>>> md.toc_tokens
[{'level': 1, 'id': 'heading', 'name': '\x02wzxhzdk:0\x03Heading\x02wzxhzdk:1\x03', 'children': []}]
```

While this isn't *too* hard to fix (we could just un-stash the HTML immediately before returning it to the user), it does raise a bigger question: what should the data format of the `name` field in `toc_tokens` be? Is it...

* Markdown (so the value would be exactly as in the source file: `<code>Heading</code>`)
* Plain text (so the value would strip HTML: `Heading`)
* HTML (similar to the Markdown format, but with HTML entities replaced, so `<code>a>b</code>` becomes `<code>a&gt;b</code>`)

In particular, this is relevant for https://github.com/mkdocs/mkdocs/pull/1970. Prior to that PR, MkDocs would build an internal representation of the TOC by parsing the HTML from `.toc`. With the change, it (tries to) use `.toc_tokens`, but fails due to this issue.

FWIW, I think MkDocs wants this to be plain text in the end, but HTML makes the most sense to me in general: after all, the purpose of this lib is to convert Markdown to HTML. (MkDocs would then just need to parse the HTML fragment and strip out the tags.)

### Additional contract requirements

- Each entry in `.toc_tokens` has a `name` field containing the heading's text with HTML tags removed but HTML entities preserved. For example, the heading `# Foo <b>Bar &amp; Baz</b>` yields the name `Foo Bar &amp; Baz`.
- Add a public function `stashedHTML2text(text, md, strip_entities=True)` in module `markdown.extensions.toc`. It returns `text` with every stashed-HTML placeholder replaced by the plain-text version of the corresponding fragment from `md.htmlStash`. When `strip_entities` is `True` (the default), both HTML tags and HTML entities are removed; when `strip_entities` is `False`, only HTML tags are removed and HTML entities are left intact.
