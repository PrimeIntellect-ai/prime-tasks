Block literal scalar fails to round trip
Starting with:
```
-
  key: |
    literal
    block
    scalar
```

Produces:
```
-
  key: |
  literal
  block
  scalar
```

Which is not a valid way to produce block literal scalars - see https://www.yaml.info/learn/quote.html#literal.

Also, most of the tests assumed that block literals don't include the line separator character.

### Additional contract requirements

- When a folded block scalar and a literal block scalar are built from the same input lines, comparing the folded scalar to the literal scalar must return exactly `-1`.
