[PARSE BUG]: Line continuations are not considered
### Problem description

As per title, line continuations should make the parser skip all the following whitespace and consume the next token.

### C++ code that can't be parsed correctly (please double-check that https://robotpy.github.io/cxxheaderparser/ has the same error)

```text
static int \
                   variable;

#pragma (this \
        should \
        not \
        trigger \
        errors)
```
