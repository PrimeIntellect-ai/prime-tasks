Trailing comma is allowed in ObjectBindingPattern
https://people.mozilla.org/~jorendorff/es6-draft.html#sec-destructuring-binding-patterns

Fixing this will fix https://github.com/STRML/JSXHint/issues/50

### Additional contract requirements

- A trailing comma in an ArrayBindingPattern must produce the diagnostic "Trailing ',' is not valid in array destructuring assignment."
