Wrong classranges optimization
Something is wrong with classranges optimizations, example here:

    $ bin/regexp-tree -e '/[^a-zA-Z0-9_!#$%&*@＠]/' -o

    Optimized: /[^\d!#$%&*@-Z_a-z＠]

With `charClassClassrangesMerge` optimization disabled I have better result:

    Expected:  /[^\w!#$%&*@＠]/

### Additional contract requirements

When merging class ranges, only word characters (`\w`) and characters written as character codes (escapes such as `\uXXXX`, `\xXX`, `\u{...}`, octal and decimal escapes) may be merged with an adjacent class range to form a larger range. A character that is neither a word character nor a character code must not be merged with an adjacent class range.
