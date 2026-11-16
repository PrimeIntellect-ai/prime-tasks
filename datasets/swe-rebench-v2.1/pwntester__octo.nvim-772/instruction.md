BUG: `escape_char()` has one to many escape (`\`) char for `"`
<!-- Here is for bug reports and feature requests ONLY!

If you're looking for help, please use the discussions forum.

-->

## Issue Description

Type: *bug report*

### Describe what happened (or what feature you want)
All types of `comments` and `suggestions` made on a `PR` have issues when passing any `"` in the comment.

### Describe what you expected to happen
A comment like: `Hello "World"` ends up as
```
Hello \"World\"
```
This is not expected behaviour. It should return as
```
Hello "World"
```

[HIDDEN]

However, I haven't tested it enough to know if this causes any regressions in other places.

### How to reproduce it (as minimally and precisely as possible)

1. Add a comment to a PR: `Octo comment add`
2. ...or a suggestion to a PR diff

### Tell us your environment
Octo.nvim version
* branch: "master"
  * commit: "111979671dd0aa9281f50867901cef9792a7b2d6"

### Anything else we need to know?
I might create a PR with this implementation when I have time, but posting this here so I don't forget the problem, and hopefully someone beat me to it!

### Additional contract requirements

- Preserve the existing behavior of escaping backslashes in comment and suggestion text.
