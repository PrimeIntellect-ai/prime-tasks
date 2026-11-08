Regex globbing broken for path including active regex characters
Paths including active regex characters such as `test+a/model` are not matched by regex globbing:

```xonsh
mkdir -p test/model
mkdir -p test+a/model
mkdir -p test*1/model
for d in `.*/model`:
    print(d)
```

Gives the following output

```output
test/model
```

## For community
⬇️  **Please click the 👍 reaction instead of leaving a `+1` or 👍  comment**
