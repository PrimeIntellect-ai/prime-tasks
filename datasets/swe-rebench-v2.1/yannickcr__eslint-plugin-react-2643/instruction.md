JSX pragma matching too strict
The current JSX pragma detector will only detect pragmas included at the beginning of a docstring comment. However, pragmas can appear in regular block comments and at any position in them.

Additionally, the current requirement to use docstring comments causes issues with other eslint plugins that lint docstrings, as `@jsx` is not a valid JSDoc identifier.

[HIDDEN]
