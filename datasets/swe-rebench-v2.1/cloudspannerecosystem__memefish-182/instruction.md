Sync lexer punctuations with ZetaSQL
Some punctuations are not yet handled in `memefish.Lexer`.
It cause panic when lexing even if parsing is not needed.

I think it is safe to add all punctuations in ZetaSQL.

https://github.com/google/zetasql/blob/194cd32b5d766d60e3ca442651d792c7fe54ea74/zetasql/parser/flex_tokenizer.l#L513-L552

- [x] `(`
- [x] `[`
- [x] `{`
- [x] `)`
- [x] `]`
- [x] `}`
- [x] `*`
- [x] `,`
- [x] `=`
- [ ] `+=` `KW_ADD_ASSIGN`
  - It seems to be used in [`options_assignment_operator`](https://sourcegraph.com/github.com/google/zetasql@194cd32b5d766d60e3ca442651d792c7fe54ea74/-/blob/zetasql/parser/bison_parser.y?L10257-10271)
- [ ] `-=` `KW_SUB_ASSIGN`
  -  It seems to be used in [`options_assignment_operator`](https://sourcegraph.com/github.com/google/zetasql@194cd32b5d766d60e3ca442651d792c7fe54ea74/-/blob/zetasql/parser/bison_parser.y?L10257-10271)
- [x] `!=`
- [x] `<=`
- [x] `<<`
- [x] `=>`
- [ ] `->` `KW_LAMBDA_ARROW`
  -  #153
- [x] `<`
- [x] `>`
- [x] `>=`
- [x] `||`
- [x] `|`
- [x] `^`
- [x] `&`
- [x] `+`
- [x] `-`
- [x] `/`
- [x] `~`
- [ ] `?`
  - [Positional parameter](https://cloud.google.com/bigquery/docs/parameterized-queries) is available in BigQuery, but Cloud Spanner has not yet supported.
    > Positional parameters are not supported
- [ ] `!`
  - It seems not to be used.
- [ ] `%`
  - GQL #99
- [ ] `|>` `KW_PIPE`
  - Pipe syntax
- [x] `@`
- [ ] `@@` `KW_DOUBLE_AT`
  - [System variables in BigQuery](https://cloud.google.com/bigquery/docs/reference/system-variables)
- [x] `.`
- [ ] `:`
  - `NEW` constructors #119
  - GQL #99
- [ ] `\` `BACKSLASH`
  - [Only for lenient macro expansion](https://sourcegraph.com/github.com/google/zetasql@194cd32b5d766d60e3ca442651d792c7fe54ea74/-/blob/zetasql/parser/bison_parser.y?L245)
- [x] `;`
- [ ] `${unquoted_identifier}` [`MACRO_INVOCATION`](https://sourcegraph.com/search?q=repo:%5Egithub%5C.com/google/zetasql%24%40194cd32b5d766d60e3ca442651d792c7fe54ea74+MACRO_INVOCATION&patternType=keyword&sm=0)
  - [internal names in ZetaSQL](https://sourcegraph.com/search?q=repo:%5Egithub%5C.com/google/zetasql%24+%27%24%27&patternType=keyword&sm=0)?
- [ ] `${decimal_digits}` [`MACRO_ARGUMENT_REFERENCE`](https://sourcegraph.com/search?q=repo:%5Egithub%5C.com/google/zetasql%24%40194cd32b5d766d60e3ca442651d792c7fe54ea74+MACRO_ARGUMENT_REFERENCE&patternType=keyword&sm=0)
- [ ] `$`
  - It seems not used.

Except `MACRO_INVOCATION` and `MACRO_ARGUMENT_REFERENCE` would be better to be implemented.

This makes `Lexer` more robust even to new lexical structures that are being tested privately.
