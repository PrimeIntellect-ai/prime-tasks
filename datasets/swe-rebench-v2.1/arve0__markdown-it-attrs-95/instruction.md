Incorrect attribute assignment for bracketed text within code within items
I came across this bug while writing a README for a javascript package.

This test fails (see https://github.com/rivy/js.markdown-it-attrs/commit/795a537a53b54ec2a877e2d710c3cc66c0eede9e in [rivy/js.markdown-it-attrs/fix.item+code](https://github.com/rivy/js.markdown-it-attrs/tree/fix.item+code))...

```
    it(replaceDelimiters('should not apply inside item lists with `code{.red}`', options), () => {
      src = '- item with `code = {.red}`';
      expected = '<ul>\n<li>item with <code>code = {.red}</code></li>\n</ul>\n';
      assert.equal(md.render(replaceDelimiters(src, options)), replaceDelimiters(expected, options));
    });
```

The bracketed text is being removed from the code section and applied as an attribute to the item. It should, I believe, stay within the code section, untouched.

Example input:
```md
- item with `code = {.red}`
```

Current output:
```html
<ul>
<li class="red">item with <code>code =</code></li>
</ul>
```

Expected output:
```html
<ul>
<li>item with <code>code = {.red}</code></li>
</ul>
```
