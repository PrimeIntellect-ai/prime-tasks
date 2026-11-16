Ignore trailing whitespace inside strings (optionally?)
Currently this lints:

```
lintr::lint("a <- '\n  \n'", lintr::trailing_whitespace_linter())
# <text>:2:1: style: Trailing whitespace is superfluous.
#
# ^~
```

But there could be any number of reasons to include trailing whitespace inside a string.
