length filter on numbers should be absolute values
Currently xq returns the number value as it is but should take the absolute values.
```sh
❯ echo -128 | jq length
128

❯ echo -128 | xq length
-128

❯ xq --version
xq 0.1.4-01d8350a1d5a9f885b2b8b5c1222eb04b742ccb3
```
