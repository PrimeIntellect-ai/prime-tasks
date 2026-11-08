Fix CLOB Newline Normalization
https://github.com/amzn/ion-tests/commit/2a1f3f4f272256108e89f1c53bfae5b3a9ede812 introduces CLOB newline normalization in text.  This is currently skipped in the parser tests.

### Additional contract requirements

- When parsing text CLOBs, normalize CRLF and standalone CR line endings to LF.
