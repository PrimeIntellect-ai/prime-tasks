[PARSE BUG]: deleted function fails to parse
### Problem description

```
void trim(std::string&&) = delete;
```
results in
```
Exception:
Traceback (most recent call last):

  File "/home/pyodide/cxxheaderparser/parser.py", line 351, in parse
    self._parse_declarations(tok, doxygen)

  File "/home/pyodide/cxxheaderparser/parser.py", line 2682, in _parse_declarations
    tok = self._next_token_must_be(",", ";")
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

  File "/home/pyodide/cxxheaderparser/parser.py", line 170, in _next_token_must_be
    raise self._parse_error(tok, "' or '".join(tokenTypes))

cxxheaderparser.errors.CxxParseError: unexpected '=', expected ',' or ';'
```


### C++ code that can't be parsed correctly (please double-check that https://robotpy.github.io/cxxheaderparser/ has the same error)

```text
void trim(std::string&&) = delete;
```

### Additional contract requirements

- The `Function` class in `cxxheaderparser.types` exposes a public attribute `deleted` (a `bool` defaulting to `False`). It is `True` when the parsed C++ function declaration includes `= delete`, and `False` otherwise.
