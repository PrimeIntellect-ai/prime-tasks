Strings are not escaped properly when marshalling in `flow` mode
Example: https://go.dev/play/p/1Va60Iv87LJ

In `flow` mode, a lot more characters need to be quoted, otherwise the resulting yaml is wrong (or even invalid).

If I unmarshal the following yaml file:
```
a:
- b
- c,d]
- e
```
into a struct annotated with `flow`, marshalling it back produces the following invalid yaml:
```
a: [b, c,d], e]
```
Expected behavior: the string with special characters is quoted, producing:
```
a: [b, "c,d]", e]
```

/cc @quentinmit

### Additional contract requirements

- The `yaml` package provides a public function `UseSingleQuote(enabled bool) yaml.EncodeOption`. When `enabled` is true, string scalars that require quoting are emitted with single quotes instead of double quotes; when `enabled` is false, they are emitted with double quotes.


- For a non-flow field tagged `yaml:"a"` containing the strings `b`, `c,d`, and `e`, emit exactly `a:\n- b\n- c,d\n- e\n`.
- With no encode options, flow-mode strings `c]` and `c}` must be double-quoted, producing exactly `a: [b, "c]", d]\n` and `a: [b, "c}", d]\n`, respectively.
