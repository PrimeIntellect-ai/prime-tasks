`\xa0` and `\x85` are stripped from the ends of header values
Given that these bytes are allowed in header values (due to `obs-text`), and are not considered whitespace by the standard, they shouldn't be stripped during header-field OWS stripping.

An example request that demonstrates the bug:
```
GET / HTTP/1.1\r\n
Test: \xa0\x85abc\x85\xa0\r\n
Host: a\r\n
\r\n
```

Waitress will see the `Test` header as having a value of `abc`, but the vast majority of other HTTP implementations will see it as having a value of `\xa0\x85abc\x85\xa0`.
