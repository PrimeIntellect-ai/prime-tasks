Bug in JSON error checking
<!-- Please replace the text in the individual sections below. -->

### Description

The rapidjson package does not have a `decoder` submodule. Since we don't have a corresponding compatibility layer, things like `json.decoder.JSONDecodeError` fail.

### To reproduce

```
$ signac init json_decoder
$ signac find '{"x": True}'
27958648a9e57fcd66ae5e31ff3359e9
$ signac find '{"x": True}'  # This is invalid JSON, the expected behavior is to raise an error indicating that the JSON is invalid
Error: module 'signac.core.json' has no attribute 'decoder'  # The actual output
```

### Additional contract requirements

- When `signac find` is given a filter argument that is not valid JSON, it exits with a non-zero status and writes an error message to standard error that indicates the JSON is invalid. The message includes the phrase `valid JSON`.
- Add a public function `parse_filter_arg(q: list[str])` in module `signac.contrib.filterparse` that parses a JSON filter argument and returns the parsed filter as a Python object. It raises `JSONDecodeError` when the JSON string is syntactically invalid.
- Add a public exception class `JSONDecodeError` in module `signac.core.json` that is raised when JSON decoding fails.
