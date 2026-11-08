Make diff output more readable
Right now the `-dry` and `-lint` diff outputs are the direct result from `cmp.Diff`. This gets the message across but it's very hard to read. The most important first step would be removing all the string array display elements, and the double quotes in each line. It's not going to be trivial, since the yaml could contain double quotes, and I'm not entirely sure what happens in that scenario.

### Additional contract requirements

- The diff output is line-oriented: every line is prefixed with `-` for a removed line, `+` for an added line, and two spaces (`  `) for an unchanged line.
- When the original and formatted content are identical, the diff output is empty.
- Double-quote characters that are part of YAML content are preserved in the displayed diff lines; only representation syntax is omitted.
