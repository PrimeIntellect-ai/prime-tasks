Double escape backward slash
I looked into this a bit more. Marshalling output from goccy/go-yaml technically matches go/yaml output, see https://go.dev/play/p/d5RQ2vH33hS
```
goccy/go-yaml:
a:
- "\\.js"

gopkg.in/yaml.v2:
a:
- \.js
```

But it seems helmfile ignores escape in double-quoted string, and uses it as is, instead of doing unescape in process.

### Additional contract requirements

- When a string is encoded in single-quoted YAML style, preserve literal backslashes in the output rather than doubling or otherwise escaping them.
