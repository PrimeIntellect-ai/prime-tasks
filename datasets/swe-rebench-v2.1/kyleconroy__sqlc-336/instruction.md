Add support for YAML
Now that version 2 of the configuration format has been merged, we should add support for reading from `sqlc.yaml`. The newer format is a bit of a chore to write in JSON.

### Additional contract requirements

- For a version 1 YAML configuration with an unknown field `foo` on line 3, report exactly: `yaml: unmarshal errors:\n  line 3: field foo not found in type config.V1GenerateSettings`.
- Both version 1 and version 2 configuration formats can be expressed in YAML and parsed by the configuration parser.
- When generating, the configuration is read from `sqlc.yaml` in the working directory.
