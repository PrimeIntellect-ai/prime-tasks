Nothing is printed if object has only Symbol properties
Kinda obvious culprit in the code there ... https://github.com/danielb2/purdy.js/blob/master/lib/index.js#L109.

    [HIDDEN]

Symbols are checked [HIDDEN].

### Additional contract requirements

- An object with only Symbol properties must be rendered with those properties rather than treated as empty.
