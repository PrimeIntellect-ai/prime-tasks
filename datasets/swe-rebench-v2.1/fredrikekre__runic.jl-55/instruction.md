Require (at least one) space before comment

### Additional contract requirements

- Formatting `a = 1  # a comment\nab = 2 # ab comment\n` must return exactly `a = 1  # a comment\nab = 2 # ab comment\n`.
- - Formatting `(a,# comment\nb)`, `(a, # comment\nb)`, and `(a,  # comment\nb)` must produce `("\n    a, # comment\n    b,\n)`. The same requirement applies with `b + b` in place of `b`. The run of spaces immediately before `#` may contain more than one space.
