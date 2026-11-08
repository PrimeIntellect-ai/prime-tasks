Option to disallow "var" keyword with esnext: true
`esnext: true` adds support for `let` and `const` which make `var` obsolete in most cases, esp. in node.js environments. It would be great to have an option to warn about variables declared with `var` since its usage is most likely a mistake in ES6 files.

### Additional contract requirements

Provide an opt-in `varstmt` option that reports a warning for each `var` declaration statement when enabled. The wording of the warning is not prescribed.
