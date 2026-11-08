Allow {{ var }} as short  for {{ fill  var }}
But with  least priority in case of ambiguity with a function name that would take no parameters (not many of those though: `toc`, and the `if`....`end`)

### Additional contract requirements

In Markdown content, `{{ var }}` renders the value of `var` just as `{{ fill var }}` does. When a bare name could be interpreted either as this variable shorthand or as an existing zero-parameter function or block, the function or block takes precedence; the variable value must not replace that behavior.
