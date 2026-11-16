cookies with ':', '_' and some other characters are quoted
Commit https://github.com/pallets/werkzeug/commit/cf0102d6443e936f95b21b69e3deb65028d6fe3b#diff-cd95d3a95564f3230d4875ac34fc9d039856b033c6b1430d5d3cc864f87cf89aR1461-R1468 changes the logic of quoting cookies without giving any explanation why.

Previously,
```
_legal_cookie_chars = frozenset(
    c.encode("ascii")
    for c in f"{string.ascii_letters}{string.digits}/=!#$%&'*+-.^_`|~:"
)
```
included `:` and `_`, now it doesn't:
```
_token_re = re.compile(r"[\w!#$%&'*+\-.^`|~]*", re.A)
```
which causes quoting whole cookie value.

https://www.rfc-editor.org/rfc/rfc6265 doesn't mention colon nor underscore at all in the context of cookie value:
```
 cookie-value      = *cookie-octet / ( DQUOTE *cookie-octet DQUOTE )
 cookie-octet      = %x21 / %x23-2B / %x2D-3A / %x3C-5B / %x5D-7E
                       ; US-ASCII characters excluding CTLs,
                       ; whitespace DQUOTE, comma, semicolon,
                       ; and backslash
```

Werkzeug version: 2.3.0
