Parsing JSON is whitespace-dependent
When a YAML contains a JSON object that's formatted without whitespace, for example `{"name":"John"}`, the parser gives the following error:
```
[1:2] failed to parse flow mapping value node
    >  1 | {"name":"John"}
```

This does not happen when fields are separated by a space, i.e. `{"name": "John"}`

Playground: https://goplay.space/#5xOT86HOV2L
