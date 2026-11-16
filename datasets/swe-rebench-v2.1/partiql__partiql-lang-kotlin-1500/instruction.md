[v1] bag constructor allows for whitespace between angle brackets
Something I noticed when trying to add some special operator parsing rules in the v1 branch is that it currently allows whitespace between the angle brackets:

```
Welcome to the PartiQL shell!
Typing mode: LEGACY
Using version: 1.0.0-SNAPSHOT-4dd09721
PartiQL> <<1>>;
==='
<<
  1
>>
---
OK!
PartiQL> < < 1 > >;
==='
<<
  1
>>
---
OK!
```

whereas the previous parsing behavior on `main` and all prior releases require the angle brackets to be together:
```
Welcome to the PartiQL shell!
Typing mode: LEGACY
Using version: 0.14.5-ab65143c
PartiQL> <<1>>;
==='
<<
  1
>>
---
OK!
PartiQL> < < 1 > >;

mismatched input '<' expecting {'ANY', 'AVG', 'BIT_LENGTH', 'CASE', 'CAST', 'CHARACTER_LENGTH', 'CHAR_LENGTH', 'COALESCE', 'COUNT', 'CREATE', 'CURRENT_DATE', 'CURRENT_USER', 'DATE', 'DELETE', 'DROP', 'EVERY', 'EXCLUDED', 'EXEC', 'EXISTS', 'EXPLAIN', 'EXTRACT', 'DATE_ADD', 'DATE_DIFF', 'FALSE', 'FROM', 'INSERT', 'LOWER', 'MAX', 'MIN', 'NOT', 'NULL', 'NULLIF', 'OCTET_LENGTH', 'OVERLAY', 'POSITION', 'REPLACE', 'SELECT', 'SET', 'SIZE', 'SOME', 'SUBSTRING', 'SUM', 'TIME', 'TIMESTAMP', 'TRIM', 'TRUE', 'UPDATE', 'UPPER', 'UPSERT', 'VALUES', 'LAG', 'LEAD', 'CAN_CAST', 'CAN_LOSSLESS_CAST', 'MISSING', 'PIVOT', 'REMOVE', 'LIST', 'SEXP', '+', '-', '@', '<<', '[', '{', '(', '?', LITERAL_STRING, LITERAL_INTEGER, LITERAL_DECIMAL, IDENTIFIER, IDENTIFIER_QUOTED, ION_CLOSURE}
```

Seems like https://github.com/partiql/partiql-lang-kotlin/pull/1449 inadvertently introduced this parsing change. Will need to confirm w/ team whether this behavior should exist in the parsing.

### Additional contract requirements

- A bag constructor whose angle brackets are separated by whitespace or comments must be rejected by throwing a `ParserException`.
- For the experimental parser target (`ParserTarget.EXPERIMENTAL`), the thrown exception must carry error code `ErrorCode.PARSE_UNEXPECTED_TOKEN` and an error context with `Property.LINE_NUMBER = 1`, `Property.COLUMN_NUMBER = 1`, `Property.TOKEN_DESCRIPTION` equal to the ANTLR display string of the `ANGLE_LEFT` token, and `Property.TOKEN_VALUE` equal to the Ion symbol `<`.
