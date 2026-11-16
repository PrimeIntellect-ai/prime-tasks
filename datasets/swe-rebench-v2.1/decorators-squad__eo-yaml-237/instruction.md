Implement Scalar Readers
At the moment, it is not possible to read a single Scalar of any kind, even though the following YAMLs are valid:

```yaml
---
somePlainScalar
...
```

```yaml
---
>
 a YAML Document containing
 only a Folded Block
 Scalar value
...
```

```yaml
---
|
  only
  one literal
  block scalar
...
```

We should have readers for these, following the pattern of mappings and sequences.

### Additional contract requirements

The readers are exposed on `YamlInput` (obtained through
`Yaml.createYamlInput(...)`) as `readPlainScalar()`, `readFoldedBlockScalar()` and
`readLiteralBlockScalar()`, each returning a `Scalar`.

- `readPlainScalar()` returns a Scalar whose value is the plain scalar's text. For the
  plain example above the value is `somePlainScalar`; for the input `scalar` it is
  `scalar`.
- `readFoldedBlockScalar()` returns a Scalar whose value is the folded block's text.
  Line breaks and indentation are not significant: collapsing every run of whitespace
  in the value to a single space and trimming it yields the folded text. For the folded
  example above that is `a YAML Document containing only a Folded Block Scalar value`;
  for a folded block whose content lines are `some folded` and `block scalar` it is
  `some folded block scalar`.
- `readLiteralBlockScalar()` returns a Scalar whose value is the literal block's text
  with the block indentation removed and the lines joined by the platform line
  separator. Leading and trailing whitespace is not significant: for the literal
  example above the value is `only` + lineSeparator + `one literal` + lineSeparator +
  `block scalar`; for a literal block whose content lines are `line1` and `line2` it is
  `line1` + lineSeparator + `line2`.
