add rule (rrd) use css repeated values
We can detect if some values can be extracted to variables.
For example if in the codebase we have multiple `padding: 1em` it can be extracted out

### Additional contract requirements

The rule is selectable through the normal rule-checking flow using the identifier `repeatedCss`.

`reportRepeatedCss()` returns one offense object per CSS property-value pair that occurs in
more than three distinct files. Each offense object uses these exact values:

- `rule`: `<text_info>rrd ~ repeated CSS</text_info>`
- `description`: `👉 <text_warn>Avoid repeating CSS properties with the same value more than 3 times across files. Consider using CSS variables or a common class.</text_warn> See: https://vue-mess-detector.webmania.cc/rules/rrd/repeated-css.html`
- `message`: `repeated CSS: (<normalized-pair>) in <N> files 🚨`, where `<normalized-pair>` is the
  property-value pair with all spaces removed (for example `color:red;`) and `<N>` is the number of
  distinct files the pair occurs in.
- `file`: the offending file paths joined with `, ` (comma followed by a space), in the order the
  files were first recorded.

`reportRepeatedCss()` logs the offending files via `console.log` before returning.
