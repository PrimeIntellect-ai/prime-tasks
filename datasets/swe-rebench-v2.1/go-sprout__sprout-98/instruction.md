misc: fix methods cases
### Please exprime yourself

Right now, it's

- toJson
- toYaml
- fromJson
- ...

But these are acronyms

It should be
- toJSON
- toYAML
- fromJSON

The code is OK I think. My problem is the identifier of methods in the template engine

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct

### Additional contract requirements

The same fully-capitalized acronym convention applies to the remaining encoding helpers, which must be exposed under these identifiers:

- `toPrettyJSON` — serializes a Go value into an indented JSON string, returning an error when encoding fails.
- `toRawJSON` — serializes a Go value into a JSON string with HTML characters left unescaped, returning an error when encoding fails.
- `fromYAML` — parses a YAML string into a Go value, returning an error on malformed input.
- `toIndentYAML` — serializes a Go value into a YAML string using the supplied indentation width, returning an error when encoding fails.
