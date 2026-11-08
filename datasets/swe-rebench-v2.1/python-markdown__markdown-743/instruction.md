Line break in link references inside lists
Hey!

Consider the following code:

```
Two things:

 - I would like to tell you about the [code of
   conduct][] we are using in this project.
 - Only one in fact.

[code of conduct]: https://github.com/Python-Markdown/markdown/blob/master/CODE_OF_CONDUCT.md
```

CommonMark is rendering the link correctly. GitHub as well (see below). PHP Markdown does render correctly too. However, Python-Markdown doesn't because of the space at the beginning of the line. I don't know if space at the beginning of a line should just be ignored inside a link or if only the exact amount of space used for list indent should be ignored.

---
Two things:

 - I would like to tell you about the [code of
   conduct][] we are using in this project.
 - Only one in fact.

[code of conduct]: https://github.com/Python-Markdown/markdown/blob/master/CODE_OF_CONDUCT.md

### Additional contract requirements

- In the rendered link, the anchor text must preserve the line break and indentation exactly: `code of` followed by an actual line break and three spaces, then `conduct`.
