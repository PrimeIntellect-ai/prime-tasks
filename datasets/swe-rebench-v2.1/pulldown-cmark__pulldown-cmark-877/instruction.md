[fuzz result] only four spaces trimmed after line break in link title
Consider this markdown:

```markdown
[link]: destination "
          text          "

[link]
```

It's another place where pulldown-cmark diverges from most other implementations. The [dingus](https://spec.commonmark.org/dingus/?text=%0A%5Blink%5D%3A%20destination%20%22%0A%20%20%20%20%20%20%20%20%20%20text%20%20%20%20%20%20%20%20%20%20%22%0A%0A%5Blink%5D%0A) thinks there's ten spaces after the word "text", but no spaces before it. [markdown-it](https://markdown-it.github.io/#md3=%7B%22source%22%3A%22%5Cn%5Blink%5D%3A%20destination%20%5C%22%5Cn%20%20%20%20%20%20%20%20%20%20text%20%20%20%20%20%20%20%20%20%20%5C%22%5Cn%5Cn%5Blink%5D%5Cn%22%2C%22defaults%22%3A%7B%22html%22%3Afalse%2C%22xhtmlOut%22%3Afalse%2C%22breaks%22%3Afalse%2C%22langPrefix%22%3A%22language-%22%2C%22linkify%22%3Atrue%2C%22typographer%22%3Atrue%2C%22_highlight%22%3Atrue%2C%22_strict%22%3Atrue%2C%22_view%22%3A%22src%22%7D%7D), [commonmark-hs](https://pandoc.org/try/?params=%7B%22text%22%3A%22%5Cn%5Blink%5D%3A+destination+%5C%22%5Cn++++++++++text++++++++++%5C%22%5Cn%5Cn%5Blink%5D%5Cn%22%2C%22to%22%3A%22html5%22%2C%22from%22%3A%22commonmark%22%2C%22standalone%22%3Afalse%2C%22embed-resources%22%3Afalse%2C%22table-of-contents%22%3Afalse%2C%22number-sections%22%3Afalse%2C%22citeproc%22%3Afalse%2C%22html-math-method%22%3A%22plain%22%2C%22wrap%22%3A%22auto%22%2C%22highlight-style%22%3Anull%2C%22files%22%3A%7B%7D%2C%22template%22%3Anull%7D), and GFM all seem to agree.

In other words, they all make this HTML:

```html
<p><a href="destination" title="
text          ">link</a></p>
```

The exception is goldmark. It does this:

```html
<p><a href="destination" title="
          text          ">link</a></p>
```

pulldown-cmark does this:

```html
<p><a href="destination" title="
      text          ">link</a></p>
```
