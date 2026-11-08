semantic-release --no-ci logs [secure]ecure][[secure]9[secu...
## Current behavior

```
$ ./node_modules/.bin/semantic-release --no-ci
[secure]ecure][[secure]9[secure]0[secure]m[secure][[secure]S[secure]e[secure]m[secure]a[secure]n[secure]t[secure]i[secure]c[secure] [secure]r[secure]e[secure]l[secure]e[secure]a[secure]s[secure]e[secure]][secure]:[secur....
```

## Expected behavior

should only mask sensitive tokens

## Environment

- **semantic-release** version: 13.1.3, 12.4.1
- Plugins used: none
- **semantic-release** configuration:
  ```json
  "release": {
    "publish": [
      "@semantic-release/npm",
      {
        "path": "@semantic-release/github",
        "assets": [
          "dist/*"
        ]
      }
    ]
  }
  ```
- CI logs: does not apply
