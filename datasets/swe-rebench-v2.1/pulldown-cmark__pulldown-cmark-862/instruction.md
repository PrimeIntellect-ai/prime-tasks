[fuzz result] code block terminators can't be indented four spaces
Try these two things out in [the dingus](https://spec.commonmark.org/dingus/?text=%20~~~%0A%20%20%20%20~~~%0A). The first one has a string, that looks like a closing fence, indented four spaces. The second one is only indented three spaces.

```markdown
 ~~~
    ~~~
```

```markdown
 ~~~
   ~~~
```

[The spec](https://spec.commonmark.org/0.31.2/#fenced-code-blocks) definitely wants the second one to be an empty code block, but it's a bit ambiguous about the first:

> The closing code fence may be preceded by up to three spaces of indentation, and may be followed only by spaces or tabs, which are ignored.

Pulldown-cmark checks "spaces of indentation" relative to the indentation level of the *opening fence*, but the reference implementation, [commonmark-hs](https://pandoc.org/try/?params=%7B%22text%22%3A%22+%7E%7E%7E%5Cn++++%7E%7E%7E%5Cn%22%2C%22to%22%3A%22html5%22%2C%22from%22%3A%22commonmark%22%2C%22standalone%22%3Afalse%2C%22embed-resources%22%3Afalse%2C%22table-of-contents%22%3Afalse%2C%22number-sections%22%3Afalse%2C%22citeproc%22%3Afalse%2C%22html-math-method%22%3A%22plain%22%2C%22wrap%22%3A%22auto%22%2C%22highlight-style%22%3Anull%2C%22files%22%3A%7B%7D%2C%22template%22%3Anull%7D) [and markdown-it](https://markdown-it.github.io/#md3=%7B%22source%22%3A%22%20~~~%5Cn%20%20%20%20~~~%22%2C%22defaults%22%3A%7B%22html%22%3Afalse%2C%22xhtmlOut%22%3Afalse%2C%22breaks%22%3Afalse%2C%22langPrefix%22%3A%22language-%22%2C%22linkify%22%3Atrue%2C%22typographer%22%3Atrue%2C%22_highlight%22%3Atrue%2C%22_strict%22%3Afalse%2C%22_view%22%3A%22html%22%7D%7D) all seem to check relative to the *start of the line*.

<details>

Events from pulldown-cmark:

```rust
" ~~~#4\n    ~~~\n" -> [
  Start(CodeBlock(Fenced(Borrowed(""))))
  End(CodeBlock)
]
```

Events from pandoc:

```rust
" ~~~#4\n    ~~~\n" -> [
  Start(CodeBlock(Fenced(Borrowed(""))))
    Text(Boxed(" ~~~"))
  End(CodeBlock)
]
```

Events from commonmark.js:

```rust
" ~~~#4\n    ~~~\n" -> [
  Start(CodeBlock(Fenced(Borrowed(""))))
    Text(Boxed(" ~~~"))
  End(CodeBlock)
]
```

AST from [pandoc](https://pandoc.org/try/?params=%7B%22text%22%3A%22%20~~~%234%5Cn%20%20%20%20~~~%5Cn%22%2C%22to%22%3A%22json%22%2C%22from%22%3A%22commonmark%22%7D):

```text
Pandoc {
    meta: {},
    blocks: [
        CodeBlock(
            Attr(
                "",
                [
                    "#4",
                ],
                [],
            ),
            "   ~~~",
        ),
    ],
}
```
