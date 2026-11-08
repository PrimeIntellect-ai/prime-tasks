Support JSON for inventory
Similar to #714, ANTA should be able to load an inventory file using `json` format

### Additional contract requirements

- `AntaInventory.parse` accepts a `file_format` argument that selects the parser used for the inventory file: `"json"` parses the file as JSON and `"yaml"` (the default) parses it as YAML.
