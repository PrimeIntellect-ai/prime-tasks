`regexp/no-invalid-regexp` for invalid regexes
**Motivation**
While developing #282, I noticed that [ESLint's `no-invalid-regexp`](https://eslint.org/docs/rules/no-invalid-regexp) only validates expression of the form `RegExp(<string literal>)`. It doesn't support the concatenation of string literals and all the fancy stuff #282 can do.

E.g. ESLint's `no-invalid-regexp` will detect `RegExp("([")` but it can't detect `RegExp("([" + "")`. We can detect this, so why not report it?

**Description**
Add a new rule `regexp/no-invalid-regexp` that behaves like ESLint `no-invalid-regexp` but uses `PatternSource` under the hood.

The best way to implement this might be to extend the `defineRegexpVisitor` to allow a new visitor type that doesn't require a parsed RegExpp AST.

**Examples**

<!-- Add a few examples of regexes that the rule does and does not report. -->

```js
/* ✓ GOOD */
var foo = RegExp("foo")
var foo = RegExp("([" + "])")

/* ✗ BAD */
var foo = RegExp("([")
var foo = new RegExp("([" + "\\" + "])", "i")
```

### Additional contract requirements

- This rule validates regular-expression pattern syntax only. Flag validity is handled separately by `regexp/no-non-standard-flag`.
- The rule validates string arguments passed to `RegExp` constructors in both the call form (`RegExp(...)`) and the constructor form (`new RegExp(...)`), including concatenated string arguments.
- For `new RegExp("(")`, report `Invalid regular expression: /(/: Unterminated group` at columns 13–14.
