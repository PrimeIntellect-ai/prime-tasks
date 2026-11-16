Can't allow `<picture>` and `<source>`
I'm trying to allow the `<picture>` and `<source>` elements in a UGCPolicy using this code:

```go
p = bluemonday.UGCPolicy()
p.AllowElements("picture", "source")
p.AllowAttrs("srcset", "src", "type", "media").OnElements("source")
p.Sanitize("<picture><source src=\"b.jpg\" media=\"(prefers-color-scheme: dark)\"></source><img src=\"a.jpg\"></picture>")
```

But no matter what I do, it seems `<picture>` element is always stripped in the output:

```
<source src="b.jpg"></source><img src="a.jpg">
```

The use case for this is allowing to provide alternative versions of an image – different resolutions or different dark/light theme version. GitHub supports this for example in their Markdown: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#specifying-the-theme-an-image-is-shown-to

Am I doing something wrong?

### Additional contract requirements

- For the shown policy and input, `Sanitize` must return exactly `<picture><source src="b.jpg" media="(prefers-color-scheme: dark)"></source><img src="a.jpg"></picture>`.
