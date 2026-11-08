Authorization.from_header with "Token" scheme cannot handle base64 padding on tokens
# Steps to reproduce

```
import base64
from werkzeug.datastructures.auth import Authorization
token = base64.encodebytes(b"This has base64 padding").decode("utf-8").strip()
a = Authorization.from_header(f"Token {token}")
a.token
```

# Expected result

```
VGhpcyBoYXMgYmFzZTY0IHBhZGRpbmc=
```

# Actual behavior

A `NoneType` is returned.

Environment:

- Python version: `Python 3.11.2 (v3.11.2:878ead1ac1, Feb  7 2023, 10:02:41) [Clang 13.0.0 (clang-1300.0.29.30)] on darwin`
- Werkzeug version: 2.3.3 / `main`
