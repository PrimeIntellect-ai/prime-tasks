`no-comment-textnodes` false positive on URL
I have JSX like the following:
```js
<strong>
  &nbsp;https://www.example.com/attachment/download/1
</strong>
```

Since the line doesn't start with `//` or `/*`, there shouldn't be any way this is identified as an accidental leaked comment.
