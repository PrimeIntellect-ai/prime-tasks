Expressions for String Arrays
Not sure if this is currently possible in tera, but it would be nice to be able to create arrays.

```
{% set vars = ["A","B","C"] %}
```

Also in for loops it would be handy:

```
{% for var in ["A","B","C"] %}
{{var}}
{% endfor %}
```

### Additional contract requirements

- An array literal evaluates to a list value. Rendering such a value directly uses
  Tera's existing list format: elements separated by `, ` and enclosed in `[` and `]`
  (for example `[1, 2]`).
- Array elements may be basic expressions (including arithmetic and function calls)
  and may be followed by filters, e.g. `["str"|upper, 1 + 1, hello()]`.
