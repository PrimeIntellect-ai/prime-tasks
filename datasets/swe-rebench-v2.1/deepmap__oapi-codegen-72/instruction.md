Make FieldName, MethodName sanitization more robust
Since there are some weird specs out there, the code-generation fails on some edge-cases like
`+, ()` in the field-name.

It would be good to have this sanitized as well

### Additional contract requirements

- For `ToCamelCase("word.word-WORD+Word_word~word(Word)Word{Word}Word[Word]Word:Word;")`, the result must be `"WordWordWORDWordWordWordWordWordWordWordWordWordWord"`.
