Text wrapped in a matching pair of one tildes is not parsed as strikethrough
[the GFM spec](https://github.github.com/gfm/#strikethrough-extension-) says:

> Strikethrough text is any text wrapped in a matching pair of one or two tildes (~).

As described in the example of the spec,

```markdown
~~Hi~~ Hello, ~there~ world!
```

should be translated to

```html
<p><del>Hi</del> Hello, <del>there</del> world!</p>
```

But `echo '~~Hi~~ Hello, ~there~ world!' | cargo run -- -T -F -S -L` shows:

```html
<p><del>Hi</del> Hello, ~there~ world!</p>
```

Only two tildes are parsed as strikethrough.
