codemod for PathReducer change of $. to $
**Problem description**:

#52  deprecates `$.` in favor of `$` which adds a breaking change

**Suggested solution**:

Create a codemod under data-point-codemds that will refactor any instance of `$.` to `$`

`'$.'` to `'$'`
`'$. |..'` to `'$ |..'`

applies to strings and string literals
