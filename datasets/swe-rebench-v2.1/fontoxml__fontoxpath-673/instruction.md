Primary error hidden if fontoxpath:evaluate is applied to a precompiled expression that throws
This was a fun one to debug - our built-in `fontoxpath:evaluate` function can be applied to both strings (direct XPath source) or elements (representing XPath ASTs). The latter form is used for Fonto Editor's `xq`. Turns out we have some type confusion around the value here in the error handling logic. This works fine in case the expression is a string, but if it's an element [HIDDEN]. This causes a crash in [HIDDEN] as it's trying to iterate over [HIDDEN] when trying to find the comment that contains the original expression.

### Additional contract requirements

- When `fontoxpath:evaluate` evaluates a precompiled expression represented by an element and that expression throws, error reporting must preserve the primary error rather than replace it with a secondary crash.
