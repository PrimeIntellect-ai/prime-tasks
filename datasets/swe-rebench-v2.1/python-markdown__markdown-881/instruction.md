Backslash escape not unescaped in ID attributes
I'm using the `TocExtension` to generate table of contens for my `.md. files (which could be relevant/irrelevant to the issue below).

In my original text, I'm escaping the single underscore `_` with a backslash:

```markdown
### select\_related
```

After running the text through `markdown`, this is the HTML result:

```HTML
<h3 id="select95related">select_related</h3>
```

And the generated TOC points to the ID above as well. I'm wondering if this is the expected behaviour? I would expect `markdown` to simply render:

```HTML
<h3 id="select_related">select_related</h3>
```

At least according to [one online converter](https://www.browserling.com/tools/markdown-to-html), the result should be: `<...id="select_related"...>`



Am I missing something?

### Additional contract requirements

When the TOC extension generates a heading ID from text containing a backslash-escaped underscore, any generated TOC link for that heading must target the corrected ID containing the unescaped underscore.
