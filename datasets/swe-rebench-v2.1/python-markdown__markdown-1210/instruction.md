link text containing backtick code doesn't work for `[]::()`
With Markdown 3.3.6, the following markdown link doesn't render properly (no output is generated):

```
[Hello `[T]::world()` link](https://example.com)
```

If I remove the inner right-bracket `]` or the following colon `:`, or the open parenthesis `(`, then it does render something.

`commonmark` 0.9.1 is able to render this link as expected:
```
<a href="https://example.com">Hello <code>[T]::world()</code> link</a>
```
